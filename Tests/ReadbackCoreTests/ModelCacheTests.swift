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
            if sharedStore {
                let stored = hub.appendingPathComponent("blobs/aa/s\(index)")
                try Data(count: size).write(to: stored)
                try fm.createSymbolicLink(atPath: blob.path, withDestinationPath: "../../blobs/aa/s\(index)")
            } else {
                try Data(count: size).write(to: blob)
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
}
