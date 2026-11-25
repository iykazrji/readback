import Testing
@testable import ReadbackCore

/// Rewriting a cleaned reply so it sounds like a person reading it, not a parser: paths say
/// their file, hashes go, symbols become words. The cases come from real replies in the
/// owner's History (2026-11-25).
@Suite struct SpokenTextTests {
    private func say(_ text: String) -> String { SpokenText.rewrite(text) }

    @Test func aPathSaysOnlyItsFile() {
        #expect(say("Fixed in Sources/Readback/Window/SetupSheet.swift today.") == "Fixed in SetupSheet dot swift today.")
        #expect(say("Look in ~/Library/Logs/Readback for it.") == "Look in Readback for it.")
        #expect(say("It lives in ~/Library/Logs/") == "It lives in Logs")
        #expect(say("Run ./scripts/build-app.sh first.") == "Run build-app dot sh first.")
    }

    @Test func aFileAndLineSaysTheLine() {
        #expect(say("See PlayerView.swift:433 for it.") == "See PlayerView dot swift, line 433, for it.")
        #expect(say("See Sources/Readback/Window/SetupSheet.swift:325.") == "See SetupSheet dot swift, line 325.")
    }

    @Test func aFileNameSaysItsDot() {
        #expect(say("Read main.py and PRODUCT.md.") == "Read main dot py and PRODUCT dot md.")
        #expect(say("Install Readback.app again.") == "Install Readback app again.")
    }

    @Test func oneSlashBetweenWordsIsLeftAlone() {
        #expect(say("Switch it on/off, and/or wait.") == "Switch it on/off, and/or wait.")
        #expect(say("The branch fix/steady-download-numbers is local.") == "The branch fix/steady-download-numbers is local.")
        #expect(say("Contrast is 3.8:1 here.") == "Contrast is 3.8:1 here.")
    }

    @Test func commitHashesGo() {
        #expect(say("Committed as d0bf2ea.") == "Committed.")
        #expect(say("Commits f3f6f2e to e3cbc37 are done.") == "Commits are done.")
        #expect(say("The fix (commit 8f76ee2) is in.") == "The fix (commit) is in.")
        // Hex-looking words that are words stay.
        #expect(say("A decade of facade work.") == "A decade of facade work.")
        #expect(say("Version 1234567 is a number.") == "Version 1234567 is a number.")
    }

    @Test func numbersAfterAHashSayNumber() {
        #expect(say("Merged #478 today.") == "Merged number 478 today.")
        #expect(say("Merged PR #9567 and issue #12.") == "Merged PR 9567 and issue 12.")
    }

    @Test func snakeCaseBecomesWords() {
        #expect(say("Set email_address and invited_by.") == "Set email address and invited by.")
    }

    @Test func symbolsBecomeWords() {
        #expect(say("Home → History") == "Home to History")
        #expect(say("input -> output") == "input to output")
        #expect(say("It's 35 × 20 now.") == "It's 35 by 20 now.")
        #expect(say("build && test") == "build and test")
        #expect(say("Use [on|off] here.") == "Use [on or off] here.")
        #expect(say("Pass --clear to uv.") == "Pass clear to uv.")
    }

    @Test func unitsAreSpelledOut() {
        #expect(say("It took 2.2s and 120ms.") == "It took 2.2 seconds and 120 milliseconds.")
        #expect(say("Controls are 34 pt and 1 pt edges, 28px.") == "Controls are 34 points and 1 point edges, 28 pixels.")
        #expect(say("About 1.4 GB.") == "About 1.4 GB.")
    }

    @Test func bareWebAddressesSayLink() {
        #expect(say("See heard.dev/compare/claude-code-text-to-speech for more.") == "See link for more.")
        #expect(say("Docs at developer.apple.com/documentation/foundationmodels today.") == "Docs at link today.")
    }

    /// Found running the rules over the owner's last 50 replies.
    @Test func whatLooksLikeAPathButIsnt() {
        #expect(say("Type /readback:speak on, or /read.") == "Type /readback:speak on, or /read.")
        #expect(say("Replies after Close/Esc/Stop stay.") == "Replies after Close/Esc/Stop stay.")
        #expect(say("The page path is /workspace/departments/[slug].") == "The page path is /workspace/departments/[slug].")
    }

    @Test func aLeadingDotKeepsItsSpace() {
        #expect(say("and .py comes out wrong") == "and dot py comes out wrong")
        #expect(say("into its ignored .local/ folder") == "into its ignored .local/ folder")
        #expect(say("what .tint covers.") == "what .tint covers.")
    }

    @Test func plainProseIsUntouched() {
        let prose = "Fixed. Two separate bugs stacked on top of each other, and I reproduced both before fixing them."
        #expect(say(prose) == prose)
    }

    @Test func theReadingPathUsesTheRewrite() {
        #expect(SpeechText.spoken("Edit `speak_reply.sh` in ~/.claude/hooks") == "Edit speak reply dot sh in hooks")
    }
}
