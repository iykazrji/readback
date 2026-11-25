import XCTest
@testable import ReadbackCore

final class SpeechTextTests: XCTestCase {
    func testStripsMarkupButKeepsWords() {
        let md = """
        ## Ok so

        This is **bold**, *italic* and `bun test`. See [the docs](https://x.y/z).
        - first item
        - second item
        """
        XCTAssertEqual(SpeechText.clean(md), """
        Ok so

        This is bold, italic and bun test. See the docs.
        first item
        second item
        """)
    }

    func testKeepsSnakeCaseAndPaths() {
        XCTAssertEqual(SpeechText.clean("Edit speak_reply.sh in ~/.claude/hooks"), "Edit speak_reply.sh in ~/.claude/hooks")
    }

    func testReplacesCodeBlocksAndTables() {
        let md = """
        Before.
        ```swift
        let a = 1
        ```
        | a | b |
        |---|---|
        | 1 | 2 |
        After.
        """
        XCTAssertEqual(SpeechText.clean(md), "Before.\n\n(code block skipped)\n\n(table skipped)\nAfter.")
    }

    func testUnclosedFenceDropsTheRest() {
        XCTAssertEqual(SpeechText.clean("Look:\n```\nhalf a block"), "Look:\n\n(code block skipped)")
    }

    func testBareUrlsBecomeLink() {
        XCTAssertEqual(SpeechText.clean("Open https://claude.ai/artifact/abc now"), "Open link now")
    }

    func testChunksNeverCrossLinesAndMergeShortSentences() {
        let chunks = SpeechText.chunks("One. Two. Three.\nNext line here.", maxChars: 40)
        XCTAssertEqual(chunks, ["One. Two. Three.", "Next line here."])
    }

    func testChunksSplitWhenTooLong() {
        let a = "The server starts when you turn read-aloud on."
        let b = "It stops again when you turn it off."
        XCTAssertEqual(SpeechText.chunks("\(a) \(b)", maxChars: 60), [a, b])
        XCTAssertEqual(SpeechText.chunks("\(a) \(b)", maxChars: 200), ["\(a) \(b)"])
    }

    func testEmptyTextHasNoChunks() {
        XCTAssertEqual(SpeechText.chunks(SpeechText.clean("  \n\n ")), [])
    }
}

final class HTTPRequestTests: XCTestCase {
    func testParsesPostWithBody() {
        let raw = "POST /speak?x=1 HTTP/1.1\r\nHost: localhost\r\nContent-Length: 4\r\n\r\nabcd"
        XCTAssertEqual(HTTPRequest.parse(Data(raw.utf8)), .complete(HTTPRequest(
            method: "POST", path: "/speak", headers: ["host": "localhost", "content-length": "4"], body: Data("abcd".utf8)
        )))
    }

    func testWaitsForTheWholeBody() {
        let raw = "POST /speak HTTP/1.1\r\nContent-Length: 10\r\n\r\nabc"
        XCTAssertEqual(HTTPRequest.parse(Data(raw.utf8)), .incomplete)
        XCTAssertEqual(HTTPRequest.parse(Data("GET / HTTP/1.1\r\n".utf8)), .incomplete)
    }

    func testRejectsHugeBodies() {
        let raw = "POST /speak HTTP/1.1\r\nContent-Length: 99999999\r\n\r\n"
        XCTAssertEqual(HTTPRequest.parse(Data(raw.utf8)), .invalid("body too large"))
    }

    func testSpeakRequestDecodesAutoplaySessionAndTool() throws {
        let json = Data(#"{"text":"hi","source":"opencode","autoplay":false,"session":"s1"}"#.utf8)
        let request = try JSONDecoder().decode(SpeakRequest.self, from: json)
        XCTAssertEqual(request.autoplay, false)
        XCTAssertEqual(request.session, "s1")
        XCTAssertEqual(request.tool, .opencode)
        XCTAssertNil(try JSONDecoder().decode(SpeakRequest.self, from: Data(#"{"text":"hi"}"#.utf8)).autoplay)
        XCTAssertEqual(SpeakRequest(text: "x", source: "Claude Code").tool, .claude)
        XCTAssertEqual(SpeakRequest(text: "x", source: "claude").tool, .claude)
        XCTAssertNil(SpeakRequest(text: "x", source: "Readback").tool)
    }

    func testSpeakTitleUsesToolAndFolder() {
        XCTAssertEqual(SpeakRequest(text: "x", source: "codex", cwd: "/Users/me/code/inkine").title, "Codex · inkine")
        XCTAssertEqual(SpeakRequest(text: "x", source: nil, cwd: nil).title, "Agent")
        XCTAssertEqual(SpeakRequest(text: "x", source: "OpenCode", cwd: "/").title, "OpenCode")
    }
}
