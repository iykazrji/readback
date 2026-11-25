import Foundation

/// What's inside Readback.app, as scripts/build-app.sh lays it out. The app, the CLI and the
/// integrations all find their files through this.
public struct AppBundle {
    /// The CLI the tools' hooks run. Contents/MacOS already holds the app's own `Readback`, and the
    /// disk ignores case, so the CLI can't live beside it.
    public static let cliPath = "Contents/Helpers/readback"
    public static let uvPath = "Contents/Helpers/uv"
    public static let claudeCodePluginFolder = "ClaudeCodePlugin"
    public static let codexPluginAssetsFolder = "CodexPluginAssets"

    public let url: URL

    public init(url: URL) { self.url = url }

    /// The app a helper inside it belongs to (…/Readback.app/Contents/Helpers/readback), or nil
    /// when the helper isn't inside an app (a `swift build` copy).
    public init?(helper: URL) {
        let app = helper.resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        guard app.pathExtension == "app" else { return nil }
        url = app
    }

    public var cli: URL { url.appendingPathComponent(Self.cliPath) }
    public var uv: URL { url.appendingPathComponent(Self.uvPath) }
    public var resources: URL { url.appendingPathComponent("Contents/Resources", isDirectory: true) }
    public var claudeCodePlugin: URL { resources.appendingPathComponent(Self.claudeCodePluginFolder, isDirectory: true) }
    public var codexPluginAssets: URL { resources.appendingPathComponent(Self.codexPluginAssetsFolder, isDirectory: true) }

    /// The integrations as this copy of the app connects them: its CLI in the hooks, its mod and
    /// artwork copied out.
    public func integrationFiles(paths: ReadbackPaths, codex: CodexRun? = CodexCLI.lazyRunner()) -> IntegrationFiles {
        IntegrationFiles(paths: paths, cli: cli.path, bundledPlugin: claudeCodePlugin, codex: codex,
                         bundledCodexAssets: codexPluginAssets)
    }
}

/// Files that hold reply text or logs are the person's alone: 0600, in folders that are 0700,
/// whatever the folders above allow (a shared or exported home, an alternate READBACK_HOME).
public enum PrivateFiles {
    /// Creates the folder owner-only. One that's already there and open to others is tightened
    /// when it can be: its files are private either way, so a folder Readback may not change
    /// (a system temp folder) is left as it is.
    public static func makeFolder(_ url: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            try fm.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            return
        }
        if let mode = (try? fm.attributesOfItem(atPath: url.path))?[.posixPermissions] as? Int, mode & 0o077 != 0 {
            try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        }
    }

    /// Replaces the file in one step. The new copy is private from the moment it exists.
    public static func write(_ data: Data, to url: URL) throws {
        let fm = FileManager.default
        try makeFolder(url.deletingLastPathComponent())
        let temp = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString)")
        guard fm.createFile(atPath: temp.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: temp.path])
        }
        guard rename(temp.path, url.path) == 0 else {
            let error = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            try? fm.removeItem(at: temp)
            throw error
        }
    }
}

/// Appends lines to Readback's log files (the app's and the CLI's), since a hook's stderr usually
/// goes nowhere anyone sees.
public enum LogFile {
    public static func append(_ line: String, to file: URL) throws {
        let fm = FileManager.default
        try PrivateFiles.makeFolder(file.deletingLastPathComponent())
        guard let handle = FileHandle(forWritingAtPath: file.path) else {
            guard fm.createFile(atPath: file.path, contents: Data(line.utf8), attributes: [.posixPermissions: 0o600]) else {
                throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: file.path])
            }
            return
        }
        defer { try? handle.close() }
        // Logs from before this version were 0644.
        chmod(file.path, 0o600)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(line.utf8))
    }
}
