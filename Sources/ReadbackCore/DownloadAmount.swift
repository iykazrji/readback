import Foundation

/// How far a download has got, as text for the meters in Voices, the player and the setup sheet.
///
/// The text keeps one width for the whole download, so nothing beside it slides: the unit comes
/// from the total and is said once ("0.16 of 3.08 GB", "42 of 355 MB"), the decimals are fixed
/// (two for GB, none for MB), and the number in so far is padded with figure spaces to the
/// total's digits. A figure space is exactly one digit wide in a font with tabular digits, so
/// the views must draw this with `.monospacedDigit()`, and put it where its left end has room
/// (right-aligned, or after a gap) so the padding doesn't read as a stray space. The byte formatter it replaces switched
/// units and decimals as the count grew ("Zero kB", "9.5 MB", "164.5 MB", "1 GB"), and every
/// change of length pushed the bar beside it. Format chosen by the owner on 2026-11-25.
public enum DownloadAmount {
    /// A digit-wide blank (U+2007).
    static let figureSpace: Character = "\u{2007}"

    /// "0.16 of 3.08 GB", or "120 MB" / "1.24 GB" while the total isn't known yet.
    /// Decimal units (1 GB = 1,000,000,000 bytes), as Finder and the voices' listed sizes use.
    public static func text(received: Int64, total: Int64?, locale: Locale = .current) -> String {
        let mark = locale.decimalSeparator ?? "."
        guard let total, total > 0 else {
            let got = max(received, 0)
            if got >= 1_000_000_000 {
                return "\(gigabytes(down: got, mark: mark)) GB"
            }
            return "\(padded(String(got / 1_000_000), to: 3)) MB"
        }
        // What's in rounds down and stops at the total, so it never reads as done before it is.
        let got = min(max(received, 0), total)
        if total >= 999_500_000 {
            let all = gigabytes(nearest: total, mark: mark)
            let part = gigabytes(down: got, mark: mark)
            return "\(padded(part, to: all.count)) of \(all) GB"
        }
        let all = String((total + 500_000) / 1_000_000)
        return "\(padded(String(got / 1_000_000), to: all.count)) of \(all) MB"
    }

    /// "40%", held at 99 until the download says it's finished. Not padded: Voices draws it at the
    /// bar's left end, where its left edge stays put and padding would show as an indent.
    public static func percent(_ fraction: Double) -> String {
        let whole = fraction.isFinite ? Int((fraction * 100).rounded(.down)) : 0
        return "\(min(max(whole, 0), 99))%"
    }

    private static func gigabytes(down bytes: Int64, mark: String) -> String {
        hundredths(bytes / 10_000_000, mark: mark)
    }

    private static func gigabytes(nearest bytes: Int64, mark: String) -> String {
        hundredths((bytes + 5_000_000) / 10_000_000, mark: mark)
    }

    /// Whole integers, not a Double, so 0.16 can't come out as 0.15 when rounding down.
    private static func hundredths(_ value: Int64, mark: String) -> String {
        let cents = value % 100
        return "\(value / 100)\(mark)\(cents < 10 ? "0" : "")\(cents)"
    }

    private static func padded(_ text: String, to width: Int) -> String {
        String(repeating: figureSpace, count: max(0, width - text.count)) + text
    }
}
