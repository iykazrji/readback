import Testing
@testable import ReadbackCore

/// When Home and the player tell the person about the natural voice.
@Suite struct NaturalVoiceNudgeTests {
    @Test func wantingANaturalVoiceWithoutTheEngineAsksForIt() {
        #expect(EngineInstall.nudge(wantsNatural: true, engine: .notInstalled) == .getIt)
    }

    @Test func someoneWhoPickedTheMacOSVoiceIsNeverAsked() {
        #expect(EngineInstall.nudge(wantsNatural: false, engine: .notInstalled) == nil)
    }

    @Test func anInstallUnderWayShowsWhicheverVoiceIsPicked() {
        #expect(EngineInstall.nudge(wantsNatural: true, engine: .installing) == .downloading)
        #expect(EngineInstall.nudge(wantsNatural: false, engine: .installing) == .downloading)
    }

    @Test func aFailedInstallOffersTryAgain() {
        #expect(EngineInstall.nudge(wantsNatural: true, engine: .failed) == .didntFinish)
        #expect(EngineInstall.nudge(wantsNatural: false, engine: .failed) == .didntFinish)
    }

    @Test(arguments: [EngineInstall.Situation.installed, .unsupported, .updating, .removalFailed])
    func otherwiseItSaysNothing(_ engine: EngineInstall.Situation) {
        #expect(EngineInstall.nudge(wantsNatural: true, engine: engine) == nil)
    }
}
