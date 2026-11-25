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

    /// Whether the model is on disk in full. For a model whose size is known, that's the bytes
    /// (a little slack for a re-published file); otherwise, weights present and no broken links.
    public func isDownloaded(_ model: String, expectedBytes: Int64? = nil) -> Bool {
        let found = contents(of: model)
        guard found.broken == 0, found.weights > 0 else { return false }
        if let expectedBytes { return Double(found.bytes) >= Double(expectedBytes) * 0.98 }
        return true
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
