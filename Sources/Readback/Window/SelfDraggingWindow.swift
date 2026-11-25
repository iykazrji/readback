import AppKit
import ReadbackCore

/// The main window, moved by the app itself when a drag starts in its title bar row.
///
/// Readback draws that row in SwiftUI (each page's title, the scrolling page under it, and the
/// page and sidebar colours), so a press there reaches the app, and AppKit hands the drag to
/// WindowServer with `performDrag(with:)`. macOS 27.2's WindowServer often drops those drags:
/// the window stays put and it logs "no client initiated window drag trait gesture to activate
/// for mouse". Native title bars aren't affected, so Finder and Safari still move. Reported as
/// FB25207761 and https://github.com/anthropics/claude-code/issues/102613; a Warp A/B on 27.2
/// found that moving the window from the drag events worked 8 times out of 8.
///
/// So on 27.2 and later, a drag AppKit asks for is followed here instead: the window tracks the
/// pointer until the button comes up. Every event still goes on to SwiftUI as before. What's
/// lost for those drags is macOS's drag-to-tile and drag-into-Mission-Control.
/// Chosen by the owner on 2026-11-25, after a probe showed every press in the row reached
/// `performDrag` and none moved the window. Check again when Apple ships a fix.
final class SelfDraggingWindow: NSWindow {
    /// Where the pointer and the window were when the drag began, while one is under way.
    private var drag: (pointer: NSPoint, origin: NSPoint)?

    /// Decided once: the OS version doesn't change under a running app.
    private static let movesItself = WindowDragWorkaround.isNeeded()

    override func performDrag(with event: NSEvent) {
        // Before 27.2 this is the system drag, exactly as before, and `drag` never gets set,
        // so sendEvent below passes everything straight through.
        guard Self.movesItself else { return super.performDrag(with: event) }
        drag = (NSEvent.mouseLocation, frame.origin)
    }

    override func sendEvent(_ event: NSEvent) {
        // A new press starts clean, so a drag whose mouse-up went elsewhere can't carry over
        // into, say, dragging a slider. If this press is a title bar drag, AppKit calls
        // performDrag while handling it, below, and that starts the next one.
        if event.type == .leftMouseDown { drag = nil }
        if let drag {
            switch event.type {
            case .leftMouseDragged:
                let pointer = NSEvent.mouseLocation
                var rect = frame
                rect.origin = NSPoint(x: drag.origin.x + pointer.x - drag.pointer.x,
                                      y: drag.origin.y + pointer.y - drag.pointer.y)
                // Keeps the title bar on a screen and out from under the menu bar, as a
                // system drag does. The screen is the one under the pointer.
                let target = NSScreen.screens.first { $0.frame.contains(pointer) } ?? screen
                setFrameOrigin(constrainFrameRect(rect, to: target).origin)
            case .leftMouseUp:
                self.drag = nil
            default:
                break
            }
        }
        super.sendEvent(event)
    }
}
