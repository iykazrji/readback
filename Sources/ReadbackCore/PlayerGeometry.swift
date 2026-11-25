import CoreGraphics

/// Where the floating player goes, as plain geometry on CGRect/CGPoint so it can be tested
/// without a display. Everything here is in Cocoa coordinates (origin bottom-left of the
/// primary screen) unless a function says it takes CoreGraphics window coordinates.
///
/// The player's place is stored relative to a screen: the offset of the panel's bottom-centre
/// from the bottom-centre of that screen's visible frame. That keeps "drag it anywhere, it
/// remembers" meaningful on whichever screen the player is shown on.
public enum PlayerGeometry {
    /// Panel bottom-centre relative to a screen's visible-frame bottom-centre.
    public struct Offset: Equatable, Sendable {
        public var dx: CGFloat
        public var dy: CGFloat
        public init(dx: CGFloat, dy: CGFloat) { self.dx = dx; self.dy = dy }
        /// Bottom centre, 24pt up.
        public static let standard = Offset(dx: 0, dy: 24)
    }

    /// CoreGraphics window bounds (origin top-left of the primary screen, y down) to Cocoa
    /// (origin bottom-left of the primary screen, y up).
    public static func cocoaRect(fromCG rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Index of the frame with the largest overlap with `rect`; nil when it overlaps none.
    /// A tie goes to the earlier frame.
    public static func indexWithLargestIntersection(of rect: CGRect, in frames: [CGRect]) -> Int? {
        var best: (index: Int, area: CGFloat)?
        for (i, frame) in frames.enumerated() {
            let hit = frame.intersection(rect)
            guard !hit.isNull, hit.width > 0, hit.height > 0 else { continue }
            let area = hit.width * hit.height
            if best == nil || area > best!.area { best = (i, area) }
        }
        return best?.index
    }

    /// Index of the frame containing the point, nil when none does.
    public static func indexContaining(_ point: CGPoint, in frames: [CGRect]) -> Int? {
        frames.firstIndex { $0.contains(point) }
    }

    /// Moves `frame` the least needed to sit fully inside `visible`. A frame bigger than
    /// `visible` is pinned to its left/bottom edge.
    public static func clamp(_ frame: CGRect, into visible: CGRect) -> CGRect {
        var out = frame
        out.origin.x = min(max(out.origin.x, visible.minX), max(visible.minX, visible.maxX - out.width))
        out.origin.y = min(max(out.origin.y, visible.minY), max(visible.minY, visible.maxY - out.height))
        return out
    }

    /// The panel's offset for a frame that was dropped somewhere on the screen with `visible`.
    public static func offset(of frame: CGRect, in visible: CGRect) -> Offset {
        Offset(dx: frame.midX - visible.midX, dy: frame.minY - visible.minY)
    }

    /// Absolute frame for an offset on a screen, clamped fully inside its visible frame.
    public static func frame(for offset: Offset, size: CGSize, in visible: CGRect) -> CGRect {
        let raw = CGRect(x: visible.midX + offset.dx - size.width / 2,
                         y: visible.minY + offset.dy,
                         width: size.width, height: size.height)
        return clamp(raw, into: visible)
    }

    /// One-time conversion of the old absolute `panelOrigin`: relative to the visible frame the
    /// old frame mostly sat on. Nil when it was on no screen (nothing sensible to keep).
    public static func migrate(oldOrigin: CGPoint, size: CGSize, visibleFrames: [CGRect]) -> Offset? {
        let old = CGRect(origin: oldOrigin, size: size)
        guard let i = indexWithLargestIntersection(of: old, in: visibleFrames) else { return nil }
        return offset(of: clamp(old, into: visibleFrames[i]), in: visibleFrames[i])
    }
}
