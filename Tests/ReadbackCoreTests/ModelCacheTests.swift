import Foundation
import Testing
@testable import ReadbackCore

@Suite struct ModelCacheTests {
    let home = URL(fileURLWithPath: "/Users/someone")

    @Test func followsHuggingFaceHubsOrderForTheCacheFolder() {
        #expect(ModelCache(environment: [:], home: home).hub.path == "/Users/someone/.cache/huggingface/hub")
        #expect(ModelCache(environment: ["XDG_CACHE_HOME": "/x"], home: home).hub.path == "/x/huggingface/hub")
        #expect(ModelCache(environment: ["HF_HOME": "~/hf", "XDG_CACHE_HOME": "/x"], home: home).hub.path == "/Users/someone/hf/hub")
        #expect(ModelCache(environment: ["HUGGINGFACE_HUB_CACHE": "/old", "HF_HOME": "/h"], home: home).hub.path == "/old")
        #expect(ModelCache(environment: ["HF_HUB_CACHE": "/new", "HUGGINGFACE_HUB_CACHE": "/old"], home: home).hub.path == "/new")
    }

    /// Lays out a model the way huggingface_hub 2.x does: snapshot → model blob → shared store.
    private func makeModel(in hub: URL, files: [String: Int], sharedStore: Bool = true) throws {
        let fm = FileManager.default
        let model = hub.appendingPathComponent("models--org--voice")
        let snapshot = model.appendingPathComponent("snapshots/abc123")
        try fm.createDirectory(at: snapshot, withIntermediateDirectories: true)
        try fm.createDirectory(at: model.appendingPathComponent("refs"), withIntermediateDirectories: true)
        try "abc123".write(to: model.appendingPathComponent("refs/main"), atomically: true, encoding: .utf8)
        try fm.createDirectory(at: model.appendingPathComponent("blobs"), withIntermediateDirectories: true)
        try fm.createDirectory(at: hub.appendingPathComponent("blobs/aa"), withIntermediateDirectories: true)
        for (index, (name, size)) in files.sorted(by: { $0.key < $1.key }).enumerated() {
            let blob = model.appendingPathComponent("blobs/b\(index)")
            // config.json is real JSON, as mlx-audio needs it, padded to the size asked for.
            let content = name == "config.json" && size >= 10
                ? Data(("{\"p\":\"" + String(repeating: "x", count: size - 8) + "\"}").utf8) : Data(count: size)
            if sharedStore {
                let stored = hub.appendingPathComponent("blobs/aa/s\(index)")
                try content.write(to: stored)
                try fm.createSymbolicLink(atPath: blob.path, withDestinationPath: "../../blobs/aa/s\(index)")
            } else {
                try content.write(to: blob)
            }
            let link = snapshot.appendingPathComponent(name)
            try fm.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
            let depth = name.split(separator: "/").count - 1
            let up = String(repeating: "../", count: depth)
            try fm.createSymbolicLink(atPath: link.path, withDestinationPath: "\(up)../../blobs/b\(index)")
        }
    }

    private func tempHub() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rb-cache-\(UUID().uuidString)/hub")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func countsTheRealBytesThroughTheSharedStore() throws {
        let hub = try tempHub()
        try makeModel(in: hub, files: ["config.json": 100, "model.safetensors": 5_000, "voices/a.safetensors": 300])
        let cache = ModelCache(environment: ["HF_HUB_CACHE": hub.path], home: home)
        let found = cache.contents(of: "org/voice")
        #expect(found.bytes == 5_400)
        #expect(found.files == 3)
        #expect(found.weights == 2)
        #expect(found.broken == 0)
        #expect(cache.isDownloaded("org/voice", expectedBytes: 5_400))
        #expect(cache.isDownloaded("org/voice"))
    }

    @Test func removingAModelFreesItsFilesInTheSharedStoreToo() throws {
        let hub = try tempHub()
        try makeModel(in: hub, files: ["config.json": 100, "model.safetensors": 5_000])
        let cache = ModelCache(environment: ["HF_HUB_CACHE": hub.path], home: home)
        // A half-finished file the download left in the model's own folder.
        try Data(count: 700).write(to: cache.folder(for: "org/voice").appendingPathComponent("blobs/x.incomplete"))

        let freed = try cache.remove("org/voice")
        #expect(freed == 5_806)   // 5,100 in the shared store, 700 half-finished, 6 in refs/main
        #expect(!FileManager.default.fileExists(atPath: cache.folder(for: "org/voice").path))
        #expect((try FileManager.default.contentsOfDirectory(atPath: hub.appendingPathComponent("blobs/aa").path)).isEmpty)
        #expect(!cache.isDownloaded("org/voice"))
        #expect(try cache.remove("org/voice") == 0)   // already gone: nothing to do
    }

    @Test func aFileAnotherModelStillUsesStays() throws {
        let hub = try tempHub()
        try makeModel(in: hub, files: ["config.json": 100, "model.safetensors": 5_000])
        let fm = FileManager.default
        let other = hub.appendingPathComponent("models--org--other/snapshots/def456")
        try fm.createDirectory(at: other, withIntermediateDirectories: true)
        try fm.createSymbolicLink(atPath: other.appendingPathComponent("model.safetensors").path,
                                  withDestinationPath: hub.appendingPathComponent("blobs/aa/s1").path)
        let cache = ModelCache(environment: ["HF_HUB_CACHE": hub.path], home: home)

        try cache.remove("org/voice")
        #expect(fm.fileExists(atPath: hub.appendingPathComponent("blobs/aa/s1").path))     // shared: kept
        #expect(!fm.fileExists(atPath: hub.appendingPathComponent("blobs/aa/s0").path))    // only ours: gone
        #expect(fm.fileExists(atPath: hub.appendingPathComponent("models--org--other").path))
    }

    /// Deep review 2026-11-26, P1-1: Cancel takes back what that download added and nothing the
    /// cache held before it: an older complete revision, the files it links to, where refs/main pointed.
    @Test func cancellingADownloadKeepsWhatWasThereBefore() throws {
        let hub = try tempHub()
        try makeModel(in: hub, files: ["config.json": 100, "model.safetensors": 5_000])
        let cache = ModelCache(environment: ["HF_HUB_CACHE": hub.path], home: home)
        let fm = FileManager.default
        let model = cache.folder(for: "org/voice")
        let before = cache.inventory(of: "org/voice")

        // The download moves refs/main to a new revision and gets part of the way.
        try "def456".write(to: model.appendingPathComponent("refs/main"), atomically: true, encoding: .utf8)
        let newSnapshot = model.appendingPathComponent("snapshots/def456")
        try fm.createDirectory(at: newSnapshot, withIntermediateDirectories: true)
        try Data(count: 900).write(to: hub.appendingPathComponent("blobs/aa/s9"))
        try fm.createSymbolicLink(atPath: model.appendingPathComponent("blobs/b9").path, withDestinationPath: "../../blobs/aa/s9")
        try fm.createSymbolicLink(atPath: newSnapshot.appendingPathComponent("config.json").path, withDestinationPath: "../../blobs/b9")
        try Data(count: 700).write(to: model.appendingPathComponent("blobs/x.incomplete"))
        #expect(!cache.isDownloaded("org/voice"), "the new revision is incomplete")

        let freed = try cache.discardDownload(of: "org/voice", since: before)
        #expect(freed == 1_600)
        #expect(fm.fileExists(atPath: hub.appendingPathComponent("blobs/aa/s0").path), "the older revision's files stay")
        #expect(fm.fileExists(atPath: hub.appendingPathComponent("blobs/aa/s1").path))
        #expect(!fm.fileExists(atPath: hub.appendingPathComponent("blobs/aa/s9").path), "what it fetched goes")
        #expect(!fm.fileExists(atPath: newSnapshot.path))
        #expect(!fm.fileExists(atPath: model.appendingPathComponent("blobs/x.incomplete").path))
        #expect(try String(contentsOf: model.appendingPathComponent("refs/main"), encoding: .utf8) == "abc123")
        #expect(cache.isDownloaded("org/voice"), "the older revision still loads")
    }

    /// A download into an empty cache goes completely, shared-store files only it links to included.
    @Test func cancellingAFirstDownloadRemovesItAll() throws {
        let hub = try tempHub()
        let cache = ModelCache(environment: ["HF_HUB_CACHE": hub.path], home: home)
        let before = cache.inventory(of: "org/voice")
        try makeModel(in: hub, files: ["config.json": 100, "model.safetensors": 5_000])
        try cache.discardDownload(of: "org/voice", since: before)
        #expect(!FileManager.default.fileExists(atPath: cache.folder(for: "org/voice").path))
        #expect((try FileManager.default.contentsOfDirectory(atPath: hub.appendingPathComponent("blobs/aa").path)).isEmpty)
    }

    /// A shared-store file another model links to stays, even when this download linked it too.
    @Test func cancellingKeepsAFileAnotherModelUses() throws {
        let hub = try tempHub()
        let cache = ModelCache(environment: ["HF_HUB_CACHE": hub.path], home: home)
        let before = cache.inventory(of: "org/voice")
        try makeModel(in: hub, files: ["config.json": 100, "model.safetensors": 5_000])
        let other = hub.appendingPathComponent("models--org--other/snapshots/def456")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: other.appendingPathComponent("model.safetensors").path,
                                                   withDestinationPath: hub.appendingPathComponent("blobs/aa/s1").path)
        try cache.discardDownload(of: "org/voice", since: before)
        #expect(FileManager.default.fileExists(atPath: hub.appendingPathComponent("blobs/aa/s1").path))
        #expect(!FileManager.default.fileExists(atPath: hub.appendingPathComponent("blobs/aa/s0").path))
    }

    @Test func worksWithoutTheSharedStoreToo() throws {
        let hub = try tempHub()
        try makeModel(in: hub, files: ["config.json": 10, "model.safetensors": 90], sharedStore: false)
        #expect(ModelCache(environment: ["HF_HUB_CACHE": hub.path], home: home).contents(of: "org/voice").bytes == 100)
    }

    @Test func aDownloadCutShortIsNotDownloaded() throws {
        let hub = try tempHub()
        // Only the small files made it: the folder exists, which the old check took as done.
        try makeModel(in: hub, files: ["config.json": 100, "tokenizer.json": 200])
        let cache = ModelCache(environment: ["HF_HUB_CACHE": hub.path], home: home)
        #expect(!cache.isDownloaded("org/voice"))
        #expect(!cache.isDownloaded("org/voice", expectedBytes: 5_000))
    }

    @Test func fewerBytesThanExpectedIsNotDownloaded() throws {
        let hub = try tempHub()
        try makeModel(in: hub, files: ["config.json": 100, "model.safetensors": 1_000])
        #expect(!ModelCache(environment: ["HF_HUB_CACHE": hub.path], home: home).isDownloaded("org/voice", expectedBytes: 3_000_000))
    }

    @Test func aBrokenLinkIsNotDownloaded() throws {
        let hub = try tempHub()
        try makeModel(in: hub, files: ["config.json": 100, "model.safetensors": 1_000])
        try FileManager.default.removeItem(at: hub.appendingPathComponent("blobs/aa/s1"))
        let cache = ModelCache(environment: ["HF_HUB_CACHE": hub.path], home: home)
        #expect(cache.contents(of: "org/voice").broken == 1)
        #expect(!cache.isDownloaded("org/voice"))
    }

    @Test func aModelThatIsNotThereIsNotDownloaded() throws {
        let cache = ModelCache(environment: ["HF_HUB_CACHE": try tempHub().path], home: home)
        #expect(!cache.isDownloaded("org/nothing"))
        #expect(cache.contents(of: "org/nothing").bytes == 0)
    }

    @Test func knowsTheSizesOfItsOwnModels() {
        #expect(VoiceCatalog.downloadBytes(for: VoiceCatalog.qwen3Model) == 3_080_138_901)
        #expect(VoiceCatalog.downloadBytes(for: VoiceCatalog.kokoroModel) == 355_322_783)
        #expect(VoiceCatalog.downloadBytes(for: "someone/else") == nil)
    }

    @Test func readsTheDownloadStepsLines() {
        #expect(ModelDownloadEvent.parse(#"{"received": 1200, "total": 3080138901}"#) == .progress(received: 1200, total: 3_080_138_901))
        #expect(ModelDownloadEvent.parse(#"{"finished": "org/voice"}"#) == .finished)
        #expect(ModelDownloadEvent.parse(#"{"error": "ConnectionError: offline"}"#) == .failed("ConnectionError: offline"))
        #expect(ModelDownloadEvent.parse("Warning: You are sending unauthenticated requests") == nil)
        #expect(ModelDownloadEvent.parse(#"{"something": 1}"#) == nil)
    }

    /// B16: done means mlx-audio can load it: config.json there, and every shard the index names.
    @Test func weightsWithoutAConfigAreNotDownloaded() throws {
        let hub = try tempHub()
        try makeModel(in: hub, files: ["model.safetensors": 1_000])
        #expect(!ModelCache(environment: ["HF_HUB_CACHE": hub.path], home: home).isDownloaded("org/voice"))
    }

    @Test func aShardTheIndexNamesMustBeThere() throws {
        let hub = try tempHub()
        try makeModel(in: hub, files: ["config.json": 10, "model-00001-of-00002.safetensors": 1_000])
        let snapshot = hub.appendingPathComponent("models--org--voice/snapshots/abc123")
        let index = #"{"metadata":{},"weight_map":{"a":"model-00001-of-00002.safetensors","b":"model-00002-of-00002.safetensors"}}"#
        try index.write(to: snapshot.appendingPathComponent("model.safetensors.index.json"), atomically: true, encoding: .utf8)
        let cache = ModelCache(environment: ["HF_HUB_CACHE": hub.path], home: home)
        #expect(!cache.isDownloaded("org/voice"), "the second shard never came")
        try Data(count: 1_000).write(to: snapshot.appendingPathComponent("model-00002-of-00002.safetensors"))
        #expect(cache.isDownloaded("org/voice"))
    }

    /// Codex review round 1, #13: a config that isn't JSON, or an index that can't be read, isn't done.
    @Test func aCorruptConfigOrIndexIsNotDownloaded() throws {
        let hub = try tempHub()
        try makeModel(in: hub, files: ["config.json": 10, "model.safetensors": 1_000])
        let cache = ModelCache(environment: ["HF_HUB_CACHE": hub.path], home: home)
        let snapshot = hub.appendingPathComponent("models--org--voice/snapshots/abc123")
        try FileManager.default.removeItem(at: snapshot.appendingPathComponent("config.json"))
        try Data(count: 10).write(to: snapshot.appendingPathComponent("config.json"))
        #expect(!cache.isDownloaded("org/voice"), "a config.json of zero bytes isn't JSON")

        try FileManager.default.removeItem(at: snapshot.appendingPathComponent("config.json"))
        try #"{"model_type":"kokoro"}"#.write(to: snapshot.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
        #expect(cache.isDownloaded("org/voice"))
        try "{ half an ind".write(to: snapshot.appendingPathComponent("model.safetensors.index.json"), atomically: true, encoding: .utf8)
        #expect(!cache.isDownloaded("org/voice"), "an index that can't be read")
    }
}
