import Foundation

/// Whether the main window should move itself during a title bar drag instead of handing the
/// drag to WindowServer. macOS 27.2's WindowServer often drops drags an app starts with
/// `performDrag(with:)` (FB25207761); see `SelfDraggingWindow` in the app. Earlier versions
/// keep the system's drag, unchanged, with its drag-to-tile and Mission Control behaviour.
/// Reports put the start at 27.2 (beta 4 and the release); none for 26 or earlier.
public enum WindowDragWorkaround {
    public static func isNeeded(on version: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion) -> Bool {
        version.majorVersion > 27 || (version.majorVersion == 27 && version.minorVersion >= 2)
    }
}
