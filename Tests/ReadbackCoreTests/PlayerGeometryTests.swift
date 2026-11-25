import CoreGraphics
import Testing
@testable import ReadbackCore

/// The user's layout: ultrawide main at 0,0 and the MacBook screen to its left at negative x.
@Suite struct PlayerGeometryTests {
    static let main = CGRect(x: 0, y: 0, width: 3440, height: 1440)
    static let side = CGRect(x: -1800, y: 0, width: 1800, height: 1169)
    // visible frames (menu bar on top, no dock to speak of)
    static let mainVisible = CGRect(x: 0, y: 0, width: 3440, height: 1415)
    static let sideVisible = CGRect(x: -1800, y: 0, width: 1800, height: 1144)
    static let size = CGSize(width: 470, height: 148)

    @Test func flipsCGBoundsToCocoa() {
        // CG: a 100x50 window 10pt below the top of a 1440-high primary screen.
        let cg = CGRect(x: 20, y: 10, width: 100, height: 50)
        let cocoa = PlayerGeometry.cocoaRect(fromCG: cg, primaryScreenHeight: 1440)
        #expect(cocoa == CGRect(x: 20, y: 1380, width: 100, height: 50))
    }

    @Test func windowOnSecondaryPicksSecondary() {
        let window = CGRect(x: -1426, y: 100, width: 860, height: 580)
        #expect(PlayerGeometry.indexWithLargestIntersection(of: window, in: [Self.main, Self.side]) == 1)
    }

    @Test func windowSpanningBothPicksTheLargerShare() {
        let mostlyMain = CGRect(x: -200, y: 100, width: 1000, height: 500)
        #expect(PlayerGeometry.indexWithLargestIntersection(of: mostlyMain, in: [Self.main, Self.side]) == 0)
        let mostlySide = CGRect(x: -900, y: 100, width: 1000, height: 500)
        #expect(PlayerGeometry.indexWithLargestIntersection(of: mostlySide, in: [Self.main, Self.side]) == 1)
    }

    @Test func windowOffEveryScreenIsNil() {
        let off = CGRect(x: 9000, y: 9000, width: 100, height: 100)
        #expect(PlayerGeometry.indexWithLargestIntersection(of: off, in: [Self.main, Self.side]) == nil)
        // touching an edge is not overlapping
        let touching = CGRect(x: 3440, y: 0, width: 100, height: 100)
        #expect(PlayerGeometry.indexWithLargestIntersection(of: touching, in: [Self.main, Self.side]) == nil)
    }

    @Test func pointPicksItsScreen() {
        #expect(PlayerGeometry.indexContaining(CGPoint(x: -5, y: 5), in: [Self.main, Self.side]) == 1)
        #expect(PlayerGeometry.indexContaining(CGPoint(x: 5, y: 5), in: [Self.main, Self.side]) == 0)
        #expect(PlayerGeometry.indexContaining(CGPoint(x: -5000, y: 5), in: [Self.main, Self.side]) == nil)
    }

    @Test func standardOffsetIsBottomCentre24Up() {
        let f = PlayerGeometry.frame(for: .standard, size: Self.size, in: Self.mainVisible)
        #expect(f.midX == Self.mainVisible.midX)
        #expect(f.minY == 24)
        let g = PlayerGeometry.frame(for: .standard, size: Self.size, in: Self.sideVisible)
        #expect(g.midX == Self.sideVisible.midX)
        #expect(g.minY == 24)
    }

    @Test func droppedPositionRoundTrips() {
        let dropped = CGRect(x: 1000, y: 600, width: 470, height: 148)
        let off = PlayerGeometry.offset(of: dropped, in: Self.mainVisible)
        #expect(PlayerGeometry.frame(for: off, size: Self.size, in: Self.mainVisible) == dropped)
        // same relative spot on the other screen, still inside it
        let other = PlayerGeometry.frame(for: off, size: Self.size, in: Self.sideVisible)
        #expect(Self.sideVisible.contains(other))
    }

    @Test func nearEdgesAreClampedInside() {
        let far = PlayerGeometry.Offset(dx: 99999, dy: 99999)
        let f = PlayerGeometry.frame(for: far, size: Self.size, in: Self.sideVisible)
        #expect(f.maxX == Self.sideVisible.maxX)
        #expect(f.maxY == Self.sideVisible.maxY)
        let low = PlayerGeometry.Offset(dx: -99999, dy: -99999)
        let g = PlayerGeometry.frame(for: low, size: Self.size, in: Self.sideVisible)
        #expect(g.minX == Self.sideVisible.minX)
        #expect(g.minY == Self.sideVisible.minY)
    }

    @Test func clampPinsOversizedFrame() {
        let big = CGRect(x: 50, y: 50, width: 5000, height: 3000)
        let c = PlayerGeometry.clamp(big, into: Self.sideVisible)
        #expect(c.origin == Self.sideVisible.origin)
    }

    @Test func migratesTheUsersSavedOrigin() throws {
        // {1791, 275}: on the main display; frame spans 1791...2261, centre 2026.
        let off = try #require(PlayerGeometry.migrate(oldOrigin: CGPoint(x: 1791, y: 275), size: Self.size,
                                                      visibleFrames: [Self.mainVisible, Self.sideVisible]))
        #expect(off == PlayerGeometry.Offset(dx: 306, dy: 275))
        let back = PlayerGeometry.frame(for: off, size: Self.size, in: Self.mainVisible)
        #expect(back.origin == CGPoint(x: 1791, y: 275))
    }

    @Test func migrationOnSecondaryAndOffScreen() throws {
        let off = try #require(PlayerGeometry.migrate(oldOrigin: CGPoint(x: -900, y: 40), size: Self.size,
                                                      visibleFrames: [Self.mainVisible, Self.sideVisible]))
        let back = PlayerGeometry.frame(for: off, size: Self.size, in: Self.sideVisible)
        #expect(back.origin == CGPoint(x: -900, y: 40))
        #expect(PlayerGeometry.migrate(oldOrigin: CGPoint(x: 9999, y: 9999), size: Self.size,
                                       visibleFrames: [Self.mainVisible, Self.sideVisible]) == nil)
    }
}
