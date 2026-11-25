/// Moving a segmented control's choice with the arrow keys: one step, wrapping round at either end.
public enum SegmentStep {
    public static func step(from index: Int, by delta: Int, count: Int) -> Int {
        guard count > 0 else { return index }
        return ((index + delta) % count + count) % count
    }
}
