import Foundation
import os

/// Writes to the unified log and to ~/Library/Logs/Readback/readback.log, so failures
/// can be read later with a plain `tail`.
enum Log {
    private static let logger = Logger(subsystem: "local.readback", category: "app")
    private static let queue = DispatchQueue(label: "local.readback.log")
    static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Readback", isDirectory: true)
    private static let file = directory.appendingPathComponent("readback.log")

    static func info(_ message: String) { write("info", message); logger.info("\(message, privacy: .public)") }
    static func error(_ message: String) { write("error", message); logger.error("\(message, privacy: .public)") }

    private static func write(_ level: String, _ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) [\(level)] \(message)\n"
        queue.async {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                if let handle = try? FileHandle(forWritingTo: file) {
                    defer { try? handle.close() }
                    try handle.seekToEnd()
                    try handle.write(contentsOf: Data(line.utf8))
                } else {
                    try Data(line.utf8).write(to: file)
                }
            } catch {
                logger.error("couldn't write log file: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
