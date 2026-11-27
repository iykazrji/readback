import ReadbackCore
import SwiftUI

/// Top of Home while "read replies out loud" is off: says until when, that replies still arrive,
/// and turns it back on. Off is easy to forget, and then Readback looks broken; this and the
/// menu bar icon's slash are there so it isn't (owner's mockup, 2026-11-26).
struct ReadingOffBanner: View {
    @ObservedObject var prefs: Preferences
    let turnOn: () -> Void

    var body: some View {
        if let until = prefs.readingOffUntil {
            // A timed off can end while Home is open: the minute tick redraws the words and,
            // once it's over, the banner goes.
            TimelineView(.everyMinute) { context in
                if until > context.date {
                    HStack(spacing: 12) {
                        Image(systemName: "speaker.slash.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ReadingOff.status(until: until, now: context.date))
                                .font(.system(size: 13, weight: .semibold))
                            Text("Replies still show up here. A play button still plays one.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 12)
                        Button("Turn on", action: turnOn)
                            .buttonStyle(.readback(.primary))
                            .controlSize(.small)
                    }
                    .padding(.horizontal, Spacing.l)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .surface()
                    .accessibilityElement(children: .contain)
                }
            }
        }
    }
}
