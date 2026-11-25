import Testing
@testable import ReadbackCore

@Suite struct DeliveryTests {
    let qwen = VoiceCatalog.qwen3Model
    let sentence = "All 42 tests pass and the player keeps its place."   // 10 words

    @Test func calmSendsTheInstructionAndASteadierTemperature() {
        let options = VoiceCatalog.speechOptions(model: qwen, delivery: .calm, text: sentence)
        #expect(options["instruct"] as? String == Delivery.calmInstruction)
        #expect(options["temperature"] as? Double == 0.6)
        #expect(options["top_k"] as? Int == 10)
        #expect(options["max_tokens"] as? Int == 10 * 20 + 60)
    }

    @Test func naturalLeavesQwenAsItComesApartFromTheLengthCap() {
        let options = VoiceCatalog.speechOptions(model: qwen, delivery: .natural, text: sentence)
        #expect(options["instruct"] == nil)
        #expect(options["temperature"] == nil)
        #expect(options["top_k"] == nil)
        #expect(options["max_tokens"] as? Int == 260)
    }

    @Test func livelySendsItsInstructionAtTheModelsOwnTemperature() {
        let options = VoiceCatalog.speechOptions(model: qwen, delivery: .lively, text: sentence)
        #expect(options["instruct"] as? String == Delivery.livelyInstruction)
        #expect(options["temperature"] == nil)
    }

    @Test func otherModelsGetNothingExtra() {
        for delivery in Delivery.allCases {
            #expect(VoiceCatalog.speechOptions(model: VoiceCatalog.kokoroModel, delivery: delivery, text: sentence).isEmpty)
            #expect(VoiceCatalog.speechOptions(model: "someone/custom", delivery: delivery, text: sentence).isEmpty)
        }
    }

    @Test func theCapGrowsWithTheSentence() {
        let short = VoiceCatalog.speechOptions(model: qwen, delivery: .calm, text: "Done.")["max_tokens"] as? Int
        let long = VoiceCatalog.speechOptions(model: qwen, delivery: .calm, text: String(repeating: "word ", count: 40))["max_tokens"] as? Int
        #expect(short == 80)
        #expect(long == 860)
    }
}
