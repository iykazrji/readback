import Foundation
import Testing
@testable import ReadbackCore

/// Only macOS 27.2 and later move the window by hand; every earlier version keeps the system drag.
@Suite struct WindowDragWorkaroundTests {
    private func on(_ major: Int, _ minor: Int, _ patch: Int = 0) -> Bool {
        WindowDragWorkaround.isNeeded(on: OperatingSystemVersion(majorVersion: major, minorVersion: minor, patchVersion: patch))
    }

    @Test func earlierVersionsKeepTheSystemDrag() {
        #expect(!on(15, 0))     // the app's minimum
        #expect(!on(15, 7, 3))
        #expect(!on(26, 0))
        #expect(!on(26, 4, 1))
        #expect(!on(27, 0))
        #expect(!on(27, 1, 9))
    }

    @Test func from27Point2TheWindowMovesItself() {
        #expect(on(27, 2))
        #expect(on(27, 2, 1))   // the build it was found on
        #expect(on(27, 3))
        #expect(on(28, 0))
    }
}
