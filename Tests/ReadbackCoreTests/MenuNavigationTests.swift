import Foundation
import Testing
@testable import ReadbackCore

/// Moving through Readback's own menus from the keyboard, the way a macOS menu behaves.
@Suite struct MenuNavigationTests {
    private let tools = ["All tools", "Claude Code", "Codex", "OpenCode"]

    @Test func opensOnTheSelectedItem() {
        #expect(MenuNavigation(titles: tools, selected: 2).highlighted == 2)
    }

    @Test func opensWithNothingHighlightedWhenNothingIsSelected() {
        #expect(MenuNavigation(titles: tools, selected: nil).highlighted == nil)
    }

    @Test func downFromNothingGoesToTheFirstItem() {
        var menu = MenuNavigation(titles: tools, selected: nil)
        menu.moveDown()
        #expect(menu.highlighted == 0)
    }

    @Test func downStopsAtTheLastItem() {
        var menu = MenuNavigation(titles: tools, selected: 3)
        menu.moveDown()
        #expect(menu.highlighted == 3)
    }

    @Test func upStopsAtTheFirstItem() {
        var menu = MenuNavigation(titles: tools, selected: 0)
        menu.moveUp()
        #expect(menu.highlighted == 0)
    }

    @Test func typingJumpsToTheFirstMatch() {
        var menu = MenuNavigation(titles: tools, selected: 0)
        menu.type("c", at: 0)
        #expect(menu.highlighted == 1)
    }

    @Test func typingMoreNarrows() {
        var menu = MenuNavigation(titles: tools, selected: 0)
        menu.type("c", at: 0)
        menu.type("o", at: 0.4)
        #expect(menu.highlighted == 2)   // "Codex"
    }

    @Test func aPauseStartsANewSearch() {
        var menu = MenuNavigation(titles: tools, selected: 0)
        menu.type("c", at: 0)
        menu.type("o", at: 1.5)
        #expect(menu.highlighted == 3)   // "OpenCode"
    }

    @Test func repeatingOneLetterCycles() {
        var menu = MenuNavigation(titles: tools, selected: 0)
        menu.type("c", at: 0)
        #expect(menu.highlighted == 1)
        menu.type("c", at: 0.3)
        #expect(menu.highlighted == 2)
        menu.type("c", at: 0.6)
        #expect(menu.highlighted == 1)   // round again
    }

    @Test func matchingIgnoresCase() {
        var menu = MenuNavigation(titles: tools, selected: 0)
        menu.type("O", at: 0)
        #expect(menu.highlighted == 3)
    }

    @Test func noMatchKeepsTheHighlight() {
        var menu = MenuNavigation(titles: tools, selected: 2)
        menu.type("z", at: 0)
        #expect(menu.highlighted == 2)
    }

    @Test func pointingAtAnItemHighlightsIt() {
        var menu = MenuNavigation(titles: tools, selected: 0)
        menu.highlight(2)
        #expect(menu.highlighted == 2)
        menu.highlight(9)   // not an item: no change
        #expect(menu.highlighted == 2)
    }

    @Test func anEmptyMenuHighlightsNothing() {
        var menu = MenuNavigation(titles: [], selected: nil)
        menu.moveDown()
        menu.type("a", at: 0)
        #expect(menu.highlighted == nil)
    }
}
