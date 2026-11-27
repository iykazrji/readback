import Foundation

/// The times "read replies out loud" can be off for, and how they're said. The owner chose the
/// three on 2026-11-26: for an hour, until the next morning, or until the person turns it back on.
public enum ReadingOff {
    /// When "until morning" ends: the next 8:00 after `now`.
    public static let morningHour = 8

    public static func forAnHour(from now: Date) -> Date { now.addingTimeInterval(60 * 60) }

    /// The next `morningHour`:00 after `now`: tomorrow's, or today's when it's still before it.
    public static func nextMorning(after now: Date, calendar: Calendar = .current) -> Date {
        let today = calendar.date(bySettingHour: morningHour, minute: 0, second: 0, of: now) ?? now
        return today > now ? today : calendar.date(byAdding: .day, value: 1, to: today) ?? today
    }

    /// The menu's name for "until morning": "Until 8 AM tomorrow", or "Until 8 AM" in the small hours.
    public static func morningLabel(now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let morning = nextMorning(after: now, calendar: calendar)
        return "Until \(describe(until: morning, now: now, calendar: calendar, locale: locale) ?? "morning")"
    }

    /// "4:30 PM", "8 AM tomorrow", "Friday 8 AM": when off ends, read the way a person says it.
    /// Nil for `Date.distantFuture`, which has no time to say.
    public static func describe(until: Date, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String? {
        guard until < .distantFuture else { return nil }
        var time = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).hour()
        if calendar.component(.minute, from: until) != 0 { time = time.minute() }
        let clock = until.formatted(time)
        if calendar.isDate(until, inSameDayAs: now) { return clock }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(until, inSameDayAs: tomorrow) {
            return "\(clock) tomorrow"
        }
        let day = until.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).weekday(.wide))
        return "\(day) \(clock)"
    }

    /// "Reading is off until 8 AM tomorrow", or "Reading is off" when it's off until turned on.
    public static func status(until: Date, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        describe(until: until, now: now, calendar: calendar, locale: locale).map { "Reading is off until \($0)" } ?? "Reading is off"
    }

    /// How long reading stays off. The menu bar, the window's sidebar and Reading all offer these
    /// three under "Turn reading off" (owner, 2026-11-27: the window got the times too, not only
    /// the menu bar).
    public enum Length: CaseIterable, Sendable {
        case hour, morning, untilOn

        /// The menu's words under "Turn reading off", in the menu bar, the sidebar and Reading:
        /// "For 1 hour", "Until 8 AM tomorrow" ("Until 8 AM" in the small hours), "Until I turn it
        /// back on".
        public func menuTitle(now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
            switch self {
            case .hour: return "For 1 hour"
            case .morning: return ReadingOff.morningLabel(now: now, calendar: calendar, locale: locale)
            case .untilOn: return "Until I turn it back on"
            }
        }
    }

    /// One of the three lengths as a menu shows it, worked out when the menu opens. A menu can sit
    /// open while the clock moves on, and a pick still means what the menu said: "Until 8 AM" seen
    /// at 7:59 and picked at 8:01 doesn't turn reading off until 8 AM the next day (review round 1,
    /// 2026-11-27).
    public struct Choice: Sendable {
        public let length: Length
        public let title: String
        /// The 8 AM the menu named when it opened.
        let morning: Date

        /// The three, in the menu's order, as they read when the menu opens at `now`.
        public static func all(now: Date, calendar: Calendar = .current, locale: Locale = .current) -> [Choice] {
            let morning = ReadingOff.nextMorning(after: now, calendar: calendar)
            return Length.allCases.map {
                Choice(length: $0, title: $0.menuTitle(now: now, calendar: calendar, locale: locale), morning: morning)
            }
        }

        /// When reading comes back if this is picked at `now`: an hour from the pick, the 8 AM the
        /// menu named, or `Date.distantFuture` (until turned back on). Nil when the 8 AM it named has
        /// already come: then nothing changes, because the quiet it offered is over.
        public func until(pickedAt now: Date) -> Date? {
            switch length {
            case .hour: return ReadingOff.forAnHour(from: now)
            case .morning: return morning > now ? morning : nil
            case .untilOn: return .distantFuture
            }
        }
    }
}
