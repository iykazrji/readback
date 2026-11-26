import Testing
@testable import ReadbackCore

/// The engine install as one meter: the engine's packages, then the voice's model. The setup
/// sheet and Voices both draw it, so closing the sheet mid-install leaves the same numbers on Voices.
@Suite struct InstallProgressTests {
    let engine: Int64 = 1_500_000_000
    let model: Int64 = 355_000_000

    @Test func itStartsAtNothingOutOfEngineAndVoiceTogether() {
        let p = EngineInstall.progress(step: nil, engineFetched: 0, engineTotal: engine, voice: .pending, voiceTotal: model)
        #expect(p.received == 0)
        #expect(p.total == engine + model)
        #expect(p.fraction == 0)
    }

    @Test func theEngineStepCountsWhatsOnDisk() {
        let p = EngineInstall.progress(step: .engine, engineFetched: 750_000_000, engineTotal: engine, voice: .pending, voiceTotal: model)
        #expect(p.received == 750_000_000)
    }

    @Test func anEngineThatFetchesMoreThanMeasuredStopsAtItsShare() {
        let p = EngineInstall.progress(step: .engine, engineFetched: engine + 90_000_000, engineTotal: engine, voice: .pending, voiceTotal: model)
        #expect(p.received == engine)
    }

    @Test func theVoiceStepBeforeItsDownloadStartsDoesntJumpAhead() {
        // A fresh install reaches the voice step a moment before the download reports anything:
        // the meter stays at the engine's share instead of leaping to 99% and falling back.
        let p = EngineInstall.progress(step: .voice, engineFetched: engine, engineTotal: engine, voice: .pending, voiceTotal: model)
        #expect(p.received == engine)
    }

    @Test func theVoiceStepAddsTheModelToAWholeEngine() {
        // A Try again that starts at the voice never fetched the engine this time, but it's in.
        let p = EngineInstall.progress(step: .voice, engineFetched: 0, engineTotal: engine, voice: .downloading(received: 100_000_000), voiceTotal: model)
        #expect(p.received == engine + 100_000_000)
    }

    @Test func aVoiceAlreadyOnDiskCountsAsFetched() {
        let p = EngineInstall.progress(step: .voice, engineFetched: engine, engineTotal: engine, voice: .onDisk, voiceTotal: model)
        #expect(p.received == engine + model)
    }

    @Test func aFinishedDownloadKeepsItsBytesWhileTheVoiceWarmsUp() {
        let p = EngineInstall.progress(step: .voice, engineFetched: engine, engineTotal: engine, voice: .fetched(model), voiceTotal: model)
        #expect(p.received == engine + model)
    }

    @Test func itNeverReadsAsDoneBeforeTheInstallEnds() {
        let p = EngineInstall.progress(step: .voice, engineFetched: engine, engineTotal: engine, voice: .fetched(model), voiceTotal: model)
        #expect(p.fraction == 0.99)
    }

    @Test func aModelOfUnknownSizeHasNoFillLevel() {
        let p = EngineInstall.progress(step: .voice, engineFetched: engine, engineTotal: engine, voice: .downloading(received: 50_000_000), voiceTotal: nil)
        #expect(p.received == engine + 50_000_000)
        #expect(p.total == nil)
        #expect(p.fraction == nil)
    }

    @Test func aDownloadLargerThanItsListedSizeGrowsTheTotal() {
        let p = EngineInstall.progress(step: .voice, engineFetched: engine, engineTotal: engine, voice: .downloading(received: model + 10), voiceTotal: model)
        #expect(p.total == engine + model + 10)
    }
}
