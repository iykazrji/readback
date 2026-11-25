import Testing
@testable import ReadbackCore

@Suite struct EngineCatalogTests {
    @Test func meloAndSopranoKnowTheirModelsAndSizes() {
        #expect(EngineKind.melo.model?.id == "mlx-community/MeloTTS-English-MLX")
        #expect(EngineKind.melo.model?.bytes == 645_477_125)
        #expect(EngineKind.soprano.model?.id == "mlx-community/Soprano-1.1-80M-bf16")
        #expect(EngineKind.soprano.model?.bytes == 283_880_888)
        #expect(VoiceCatalog.downloadBytes(for: VoiceCatalog.meloModel) == 645_477_125)
        #expect(VoiceCatalog.downloadBytes(for: VoiceCatalog.sopranoModel) == 283_880_888)
        #expect(EngineKind.melo.needsRuntime && EngineKind.soprano.needsRuntime)
    }

    /// The ids must match the model's spk2id, or MeloTTS quietly falls back to its default speaker.
    @Test func meloAccentsAreTheModelsSpeakers() {
        #expect(Set(VoiceCatalog.meloVoices.map(\.id)) == ["EN-US", "EN-BR", "EN-AU", "EN_INDIA", "EN-Default"])
        #expect(VoiceCatalog.defaultVoice(for: .melo) == "EN-US")
        #expect(VoiceCatalog.meloVoices.contains { $0.id == VoiceCatalog.defaultVoice(for: .melo) })
    }

    @Test func sopranoHasOneVoiceAndNoLanguageCode() {
        #expect(VoiceCatalog.defaultVoice(for: .soprano) == "")
        #expect(VoiceCatalog.lang(for: "", engine: .soprano) == "")
        #expect(VoiceCatalog.lang(for: "EN-US", engine: .melo) == "")
    }

    @Test func neitherTakesQwensDeliveryOptions() {
        for delivery in Delivery.allCases {
            #expect(VoiceCatalog.speechOptions(model: VoiceCatalog.meloModel, delivery: delivery, text: "Hello there.").isEmpty)
            #expect(VoiceCatalog.speechOptions(model: VoiceCatalog.sopranoModel, delivery: delivery, text: "Hello there.").isEmpty)
        }
    }

    @Test func theDownloadStepFetchesMelosExtrasToo() {
        #expect(ModelDownloadScript.source.contains("\"MeloTTS\" in model"))
        #expect(ModelDownloadScript.source.contains("bert-base-uncased"))
        #expect(ModelDownloadScript.source.contains("G2p()"))
    }
}
