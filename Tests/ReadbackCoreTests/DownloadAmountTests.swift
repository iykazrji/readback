import Foundation
import Testing
@testable import ReadbackCore

/// The download meters' text: one unit, fixed decimals, and one width for the whole download.
@Suite struct DownloadAmountTests {
    private let us = Locale(identifier: "en_US")
    private let figure = "\u{2007}"

    @Test func aGigabyteTotalShowsBothNumbersInGigabytesWithTwoDecimals() {
        let total = VoiceCatalog.qwen3Bytes   // 3,080,138,901
        #expect(DownloadAmount.text(received: 0, total: total, locale: us) == "0.00 of 3.08 GB")
        #expect(DownloadAmount.text(received: 512_000, total: total, locale: us) == "0.00 of 3.08 GB")
        #expect(DownloadAmount.text(received: 164_500_000, total: total, locale: us) == "0.16 of 3.08 GB")
        #expect(DownloadAmount.text(received: 1_240_000_000, total: total, locale: us) == "1.24 of 3.08 GB")
    }

    @Test func aMegabyteTotalShowsWholeMegabytesPaddedToTheTotalsDigits() {
        let total = VoiceCatalog.kokoroBytes   // 355,322,783
        #expect(DownloadAmount.text(received: 0, total: total, locale: us) == "\(figure)\(figure)0 of 355 MB")
        #expect(DownloadAmount.text(received: 42_900_000, total: total, locale: us) == "\(figure)42 of 355 MB")
        #expect(DownloadAmount.text(received: 324_263_727, total: total, locale: us) == "324 of 355 MB")
    }

    /// Every string one download shows has the same characters in the same places, digits aside,
    /// so with tabular digits (a figure space is a digit wide) the label never changes width.
    @Test func everyAmountOfOneDownloadHasTheSameShape() {
        let totals: [Int64] = [VoiceCatalog.kokoroBytes, VoiceCatalog.qwen3Bytes, VoiceCatalog.meloBytes,
                               VoiceCatalog.sopranoBytes, 12_400_000_000, 7_000_000]
        for total in totals {
            let step = Int(max(1, total / 997))
            let shapes = Set(stride(from: Int64(0), through: total, by: step).map { (got: Int64) in
                shape(DownloadAmount.text(received: got, total: total, locale: us))
            })
            #expect(shapes.count == 1, "total \(total): \(shapes)")
        }
    }

    @Test func receivedNeverRoundsUpToTheTotalOrPastIt() {
        let total = VoiceCatalog.qwen3Bytes
        #expect(DownloadAmount.text(received: 3_079_000_000, total: total, locale: us) == "3.07 of 3.08 GB")
        #expect(DownloadAmount.text(received: 3_200_000_000, total: total, locale: us) == "3.08 of 3.08 GB")
        #expect(DownloadAmount.text(received: 354_900_000, total: VoiceCatalog.kokoroBytes, locale: us) == "354 of 355 MB")
    }

    @Test func aTotalJustUnderAGigabyteReadsAsGigabytesNotAThousandMegabytes() {
        #expect(DownloadAmount.text(received: 500_000_000, total: 999_700_000, locale: us) == "0.50 of 1.00 GB")
    }

    @Test func withoutATotalItShowsWhatsInSoFar() {
        #expect(DownloadAmount.text(received: 0, total: nil, locale: us) == "\(figure)\(figure)0 MB")
        #expect(DownloadAmount.text(received: 120_400_000, total: nil, locale: us) == "120 MB")
        #expect(DownloadAmount.text(received: 1_240_000_000, total: nil, locale: us) == "1.24 GB")
    }

    @Test func theDecimalMarkFollowsTheLocale() {
        let german = Locale(identifier: "de_DE")
        #expect(DownloadAmount.text(received: 1_240_000_000, total: VoiceCatalog.qwen3Bytes, locale: german) == "1,24 of 3,08 GB")
    }

    @Test func thePercentRoundsDownAndStopsAt99() {
        #expect(DownloadAmount.percent(0) == "0%")
        #expect(DownloadAmount.percent(0.054) == "5%")
        #expect(DownloadAmount.percent(0.409) == "40%")
        #expect(DownloadAmount.percent(0.999) == "99%")
        #expect(DownloadAmount.percent(1) == "99%")
        #expect(DownloadAmount.percent(-0.2) == "0%")
        #expect(DownloadAmount.percent(.nan) == "0%")
    }

    /// Digits and figure spaces become "#", so two strings match when they'd be the same width.
    private func shape(_ text: String) -> String {
        String(text.map { $0.isNumber || String($0) == figure ? "#" : $0 })
    }
}
