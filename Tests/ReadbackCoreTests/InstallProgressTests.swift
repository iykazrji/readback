import Testing
@testable import ReadbackCore

/// The engine install as one meter: the engine's packages, then the voice's model. The setup
/// sheet and Voices both draw it, so closing the sheet mid-install leaves the same numbers on Voices.
@Suite struct InstallProgressTests {
    let engine: Int64 = 1_500_000_000
    let model: Int64 = 355_000_000

    @Test func itStartsAtNothingOutOfEngineAndVoiceTogether() {
        let p = EngineInstall.progress(step: nil, engineFetched: 0, engineTotal: engine, modelReceived: nil, modelTotal: model)
        #expect(p.received == 0)
        #expect(p.total == engine + model)
        #expect(p.fraction == 0)
    }

    @Test func theEngineStepCountsWhatsOnDisk() {
        let p = EngineInstall.progress(step: .engine, engineFetched: 750_000_000, engineTotal: engine, modelReceived: nil, modelTotal: model)
        #expect(p.received == 750_000_000)
    }

    @Test func anEngineThatFetchesMoreThanMeasuredStopsAtItsShare() {
        let p = EngineInstall.progress(step: .engine, engineFetched: engine + 90_000_000, engineTotal: engine, modelReceived: nil, modelTotal: model)
        #expect(p.received == engine)
    }

    @Test func theVoiceStepAddsTheModelToAWholeEngine() {
        // A Try again that starts at the voice never fetched the engine this time, but it's in.
        let p = EngineInstall.progress(step: .voice, engineFetched: 0, engineTotal: engine, modelReceived: 100_000_000, modelTotal: model)
        #expect(p.received == engine + 100_000_000)
    }

    @Test func aVoiceAlreadyOnDiskCountsAsFetched() {
        let p = EngineInstall.progress(step: .voice, engineFetched: engine, engineTotal: engine, modelReceived: nil, modelTotal: model)
        #expect(p.received == engine + model)
    }

    @Test func itNeverReadsAsDoneBeforeTheInstallEnds() {
        let p = EngineInstall.progress(step: .voice, engineFetched: engine, engineTotal: engine, modelReceived: model, modelTotal: model)
        #expect(p.fraction == 0.99)
    }

    @Test func aModelOfUnknownSizeGrowsTheTotalAsItComes() {
        let p = EngineInstall.progress(step: .voice, engineFetched: engine, engineTotal: engine, modelReceived: 50_000_000, modelTotal: 0)
        #expect(p.received == engine + 50_000_000)
        #expect(p.total == engine + 50_000_000)
    }
}
