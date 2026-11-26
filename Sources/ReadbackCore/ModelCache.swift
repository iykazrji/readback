import Foundation

/// The Hugging Face cache the on-device engine downloads models into, read the way
/// huggingface_hub lays it out: `models--<org>--<name>/snapshots/<commit>/<file>` symlinks into
/// that model's `blobs/`, and since huggingface_hub 2.x most of those point on into a shared
/// store at `<hub>/blobs/`. So a model's own folder looks tiny even when it's all there;
/// only following the links gives the real size.
public struct ModelCache {
    public let hub: URL

    /// Resolves the folder the way huggingface_hub does: HF_HUB_CACHE, then the older
    /// HUGGINGFACE_HUB_CACHE, then HF_HOME/hub, then XDG_CACHE_HOME/huggingface/hub, then
    /// ~/.cache/huggingface/hub. The engine inherits Readback's environment, so both agree.
    public init(environment: [String: String] = ProcessInfo.processInfo.environment,
                home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        func path(_ key: String) -> URL? {
            guard let value = environment[key], !value.isEmpty else { return nil }
            let expanded = value.hasPrefix("~") ? home.path + value.dropFirst() : value
            return URL(fileURLWithPath: expanded, isDirectory: true)
        }
        if let hub = path("HF_HUB_CACHE") ?? path("HUGGINGFACE_HUB_CACHE") {
            self.hub = hub
        } else {
            let hfHome = path("HF_HOME")
                ?? (path("XDG_CACHE_HOME") ?? home.appendingPathComponent(".cache", isDirectory: true))
                    .appendingPathComponent("huggingface", isDirectory: true)
            hub = hfHome.appendingPathComponent("hub", isDirectory: true)
        }
    }

    public func folder(for model: String) -> URL {
        hub.appendingPathComponent("models--" + model.replacingOccurrences(of: "/", with: "--"), isDirectory: true)
    }

    /// The snapshot `refs/main` points at, or the newest one when there's no ref.
    public func snapshot(for model: String) -> URL? {
        let snapshots = folder(for: model).appendingPathComponent("snapshots", isDirectory: true)
        let fm = FileManager.default
        if let ref = try? String(contentsOf: folder(for: model).appendingPathComponent("refs/main"), encoding: .utf8) {
            let commit = ref.trimmingCharacters(in: .whitespacesAndNewlines)
            let url = snapshots.appendingPathComponent(commit, isDirectory: true)
            if fm.fileExists(atPath: url.path) { return url }
        }
        let names = (try? fm.contentsOfDirectory(at: snapshots, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return names.max { modified($0) < modified($1) }
    }

    /// What the model's files come to once every link is followed, and whether any link is broken.
    public func contents(of model: String) -> (bytes: Int64, files: Int, weights: Int, broken: Int) {
        guard let snapshot = snapshot(for: model),
              let walker = FileManager.default.enumerator(at: snapshot, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey])
        else { return (0, 0, 0, 0) }
        var bytes: Int64 = 0, files = 0, weights = 0, broken = 0
        for case let url as URL in walker {
            let real = url.resolvingSymlinksInPath()
            var isFolder: ObjCBool = false
            // fileExists follows links, so a link to a blob that isn't there comes back false
            // (resolvingSymlinksInPath leaves such a link as it is rather than failing).
            guard FileManager.default.fileExists(atPath: real.path, isDirectory: &isFolder) else {
                broken += 1
                continue
            }
            guard !isFolder.boolValue,
                  let values = try? real.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else { continue }
            files += 1
            bytes += Int64(values.fileSize ?? 0)
            if ["safetensors", "npz", "pth", "bin"].contains(url.pathExtension) { weights += 1 }
        }
        return (bytes, files, weights, broken)
    }

    /// Whether the model is on disk in full, as mlx-audio needs it to load: no broken links,
    /// weights, its config.json (mlx-audio refuses a model without one), and every shard a
    /// `*.safetensors.index.json` names. A known size has to add up too (a little slack for a
    /// re-published file).
    public func isDownloaded(_ model: String, expectedBytes: Int64? = nil) -> Bool {
        let found = contents(of: model)
        guard found.broken == 0, found.weights > 0, let snapshot = snapshot(for: model) else { return false }
        guard let config = FileManager.default.contents(atPath: snapshot.appendingPathComponent("config.json").path),
              (try? JSONSerialization.jsonObject(with: config)) is [String: Any],
              let shards = indexedShards(in: snapshot) else { return false }
        for shard in shards where !isRegularFile(snapshot.appendingPathComponent(shard)) { return false }
        if let expectedBytes { return Double(found.bytes) >= Double(expectedBytes) * 0.98 }
        return true
    }

    /// The weight files the snapshot's safetensors indexes list; nil when an index is there but
    /// can't be read (a download cut short), so the model doesn't count as complete.
    private func indexedShards(in snapshot: URL) -> Set<String>? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: snapshot.path)) ?? []
        var shards: Set<String> = []
        for name in names where name.hasSuffix(".safetensors.index.json") {
            guard let data = FileManager.default.contents(atPath: snapshot.appendingPathComponent(name).path),
                  let index = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let map = index["weight_map"] as? [String: String] else { return nil }
            shards.formUnion(map.values)
        }
        return shards
    }

    /// Through any links: a file, not a folder or a dangling link.
    private func isRegularFile(_ url: URL) -> Bool {
        (try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }

    /// Deletes a model from the cache, whole or half downloaded: its folder, and the files in the
    /// shared store that only its links point to. A file another model's links also point to
    /// stays. Returns the bytes freed.
    @discardableResult
    public func remove(_ model: String) throws -> Int64 {
        let fm = FileManager.default
        let mine = folder(for: model)
        guard fm.fileExists(atPath: mine.path) else { return 0 }
        let hubPath = hub.resolvingSymlinksInPath().path + "/"
        let others = ((try? fm.contentsOfDirectory(at: hub, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("models--") && $0.lastPathComponent != mine.lastPathComponent }
        let elsewhere = others.reduce(into: Set<String>()) { $0.formUnion(Self.linkTargets(in: $1)) }
        var freed: Int64 = 0
        for target in Self.linkTargets(in: mine) where target.hasPrefix(hubPath) && !elsewhere.contains(target) {
            // Inside the model's own folder goes with the folder below; only the shared store's here.
            guard !target.hasPrefix(mine.resolvingSymlinksInPath().path + "/") else { continue }
            freed += ((try? fm.attributesOfItem(atPath: target)[.size]) as? NSNumber)?.int64Value ?? 0
            try fm.removeItem(atPath: target)
        }
        freed += Self.bytes(in: mine)
        try fm.removeItem(at: mine)
        return freed
    }

    /// What one model's cache held at a moment: everything under its folder (not following links),
    /// the files in the shared store, and what its refs said. Taken before a download starts, so
    /// Cancel takes back what that download added and nothing that was already there: an older
    /// revision, files another program fetched, where refs/main pointed.
    public struct Inventory: Equatable {
        fileprivate let existed: Bool
        fileprivate let paths: Set<String>
        fileprivate let shared: Set<String>
        fileprivate let refs: [String: Data]
    }

    public func inventory(of model: String) -> Inventory {
        let mine = folder(for: model)
        let fm = FileManager.default
        let paths = Self.entries(in: mine)
        var refs: [String: Data] = [:]
        for path in paths where path.hasPrefix("refs/") {
            if let data = fm.contents(atPath: mine.appendingPathComponent(path).path) { refs[path] = data }
        }
        return Inventory(existed: fm.fileExists(atPath: mine.path), paths: paths, shared: sharedStoreFiles(), refs: refs)
    }

    /// Cancel: removes what was added to the model's cache since `before`, the shared-store files
    /// only it links to included, and puts its refs back. A model that wasn't there before goes
    /// completely. Returns the bytes freed.
    @discardableResult
    public func discardDownload(of model: String, since before: Inventory) throws -> Int64 {
        let fm = FileManager.default
        let mine = folder(for: model)
        guard fm.fileExists(atPath: mine.path) else { return 0 }
        let hubPath = hub.resolvingSymlinksInPath().path + "/"
        let minePath = mine.resolvingSymlinksInPath().path + "/"
        let elsewhere = otherModels(than: mine).reduce(into: Set<String>()) { $0.formUnion(Self.linkTargets(in: $1)) }
        var freed: Int64 = 0
        for target in Self.linkTargets(in: mine)
        where target.hasPrefix(hubPath) && !target.hasPrefix(minePath) && !before.shared.contains(target) && !elsewhere.contains(target) {
            freed += Self.size(atPath: target)
            try fm.removeItem(atPath: target)
        }
        guard before.existed else {
            freed += Self.bytes(in: mine)
            try fm.removeItem(at: mine)
            return freed
        }
        // Deepest first, so a folder it made is empty by the time it's reached.
        for path in Self.entries(in: mine).subtracting(before.paths).sorted(by: { $0.count > $1.count }) {
            let url = mine.appendingPathComponent(path)
            let type = (try? fm.attributesOfItem(atPath: url.path))?[.type] as? FileAttributeType
            if type == .typeDirectory {
                if (try? fm.contentsOfDirectory(atPath: url.path))?.isEmpty == true { try fm.removeItem(at: url) }
                continue
            }
            if type == .typeRegular { freed += Self.size(atPath: url.path) }
            try fm.removeItem(at: url)
        }
        for (path, data) in before.refs where fm.contents(atPath: mine.appendingPathComponent(path).path) != data {
            try data.write(to: mine.appendingPathComponent(path), options: .atomic)
        }
        return freed
    }

    private func otherModels(than mine: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: hub, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("models--") && $0.lastPathComponent != mine.lastPathComponent }
    }

    /// The real files outside every model's own folder (the shared store), as resolved paths.
    private func sharedStoreFiles() -> Set<String> {
        let fm = FileManager.default
        let top = ((try? fm.contentsOfDirectory(at: hub, includingPropertiesForKeys: nil)) ?? [])
            .filter { !$0.lastPathComponent.hasPrefix("models--") }
        var files: Set<String> = []
        for entry in top {
            for path in Self.entries(in: entry) {
                let url = entry.appendingPathComponent(path)
                if (try? fm.attributesOfItem(atPath: url.path))?[.type] as? FileAttributeType == .typeRegular {
                    files.insert(url.resolvingSymlinksInPath().path)
                }
            }
        }
        return files
    }

    /// Every path under `folder`, relative to it, without following links.
    private static func entries(in folder: URL) -> Set<String> {
        guard let walker = FileManager.default.enumerator(atPath: folder.path) else { return [] }
        var paths: Set<String> = []
        for case let path as String in walker { paths.insert(path) }
        return paths
    }

    private static func size(atPath path: String) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: path)[.size]) as? NSNumber)?.int64Value ?? 0
    }

    /// Where every link under `folder` really points, as resolved paths.
    private static func linkTargets(in folder: URL) -> Set<String> {
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isSymbolicLinkKey]) else { return [] }
        var targets: Set<String> = []
        for case let url as URL in walker where (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            let real = url.resolvingSymlinksInPath()
            if FileManager.default.fileExists(atPath: real.path) { targets.insert(real.path) }
        }
        return targets
    }

    /// The real files under `folder`, not following links.
    private static func bytes(in folder: URL) -> Int64 {
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in walker {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]), values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    private func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}

/// One line from the download step Readback runs before the engine loads a new model
/// (see `ModelDownloadScript`): JSON with how far it's got, that it finished, or why it stopped.
public enum ModelDownloadEvent: Equatable {
    /// `received`: bytes in so far. `total`: what the files add up to, as far as it knows yet.
    case progress(received: Int64, total: Int64)
    case finished
    case failed(String)

    public static func parse(_ line: String) -> ModelDownloadEvent? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let error = object["error"] as? String { return .failed(error) }
        if object["finished"] != nil { return .finished }
        if let received = (object["received"] as? NSNumber)?.int64Value,
           let total = (object["total"] as? NSNumber)?.int64Value {
            return .progress(received: received, total: total)
        }
        return nil
    }
}

/// The Python the download step runs inside the engine's own environment. It downloads exactly
/// what mlx-audio's loader would (same file patterns, same cache), through a progress class
/// that prints a JSON line at most four times a second. The bars huggingface_hub draws itself
/// switch off without a terminal, and hf_xet only writes each file out at the end, so neither
/// the log nor the disk shows progress on a big file; this does.
public enum ModelDownloadScript {
    public static let source = #"""
import json, os, sys, time
model = sys.argv[1]
def say(**fields):
    print(json.dumps(fields), flush=True)
try:
    if os.path.exists(os.path.expanduser(model)):
        say(finished=model)   # a folder on disk: nothing to download
        sys.exit(0)
    from tqdm import tqdm
    from huggingface_hub import snapshot_download
    from mlx_audio.utils import DEFAULT_ALLOW_PATTERNS
    state = {"received": 0, "written": 0, "total": 0, "last": 0.0}
    class Report(tqdm):
        def __init__(self, *args, **kwargs):
            kwargs.pop("name", None)
            kwargs["file"] = open(os.devnull, "w")
            kwargs["disable"] = False
            super().__init__(*args, **kwargs)
        def update(self, n=1):
            result = super().update(n)
            if self.unit != "B":
                return result
            desc = str(self.desc)
            if desc.startswith("Downloading bytes") or desc.startswith("Download complete"):
                state["received"] = self.n   # network bytes, smooth while a file streams in
            else:
                state["written"] = self.n    # bytes written, a whole file at a time
                state["total"] = max(state["total"], self.total or 0)
            now = time.monotonic()
            if state["received"] > 0 and now - state["last"] >= 0.25:
                state["last"] = now
                say(received=max(state["received"], state["written"]), total=state["total"])
            return result
    snapshot_download(model, allow_patterns=DEFAULT_ALLOW_PATTERNS, tqdm_class=Report)
    if "MeloTTS" in model:
        # MeloTTS also needs a BERT tokenizer and nltk's word lists, fetched the first time it
        # reads; fetch them now, so the first reply doesn't stop for them.
        from transformers import AutoTokenizer
        AutoTokenizer.from_pretrained("bert-base-uncased")
        from g2p_en import G2p
        G2p()("Ready.")
    say(finished=model)
except Exception as error:
    say(error=f"{type(error).__name__}: {error}"[:300])
    sys.exit(1)
"""#
}
