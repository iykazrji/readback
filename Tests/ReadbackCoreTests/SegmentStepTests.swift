import Testing
@testable import ReadbackCore

/// Moving a segmented control's choice with the arrow keys: one step, wrapping at either end.
@Suite struct SegmentStepTests {
    @Test func rightMovesOne() {
        #expect(SegmentStep.step(from: 0, by: 1, count: 3) == 1)
    }

    @Test func wrapsAtTheEnd() {
        #expect(SegmentStep.step(from: 2, by: 1, count: 3) == 0)
        #expect(SegmentStep.step(from: 0, by: -1, count: 3) == 2)
    }

    @Test func emptyStaysPut() {
        #expect(SegmentStep.step(from: 0, by: 1, count: 0) == 0)
    }
}
