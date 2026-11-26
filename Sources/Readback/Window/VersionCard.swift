import ReadbackCore
import SwiftUI

/// The bottom of the sidebar: "Readback 0.5.0" (opens About) and, under it, "Check for updates".
/// The card grows only when there's something to say: a newer version, a download, a failure.
/// Variant 2 of the mockup the owner picked on 2026-11-26 (a line under the version, not an
/// arrow inside the tile). Copy is the spec's: docs/superpowers/specs/2026-11-26-update-check-design.md.
struct VersionCard: View {
    @ObservedObject var updater: Updater
    @ObservedObject var downloads: ModelDownloads
    @ObservedObject var runtime: Runtime
    @ObservedObject var connections: Connections
    let aboutSelected: Bool
    let openAbout: () -> Void

    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(radius: Radius.sidebarCard, emphasis: aboutSelected ? .active : hovering ? .hovered : .resting, on: .sidebar)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .animation(Motion.reveal(reduceMotion), value: updater.card)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Readback \(Bundle.main.version)")
    }

    @ViewBuilder private var content: some View {
        switch updater.card {
        case .rest:
            versionLine
            CheckLine(title: "Check for updates", turning: false, action: updater.check)
        case .checking:
            versionLine
            CheckLine(title: "Checking\u{2026}", turning: true, action: {})
                .disabled(true)
        case .upToDate:
            HStack(spacing: 6) {
                versionLine
                Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).accessibilityHidden(true)
            }
            note("You have the newest version.")
        case .available(let release):
            heading("Readback \(release.version) is out")
            note(wait?.message ?? "You have \(Bundle.main.version).")
            Button(action: updater.install) {
                Text("Install and relaunch").frame(maxWidth: .infinity)
            }
                .buttonStyle(.readback(.primary))
                .controlSize(.small)
                .disabled(wait != nil)
                .padding(.top, 10)
            pageLink("What\u{2019}s new", release)
        case .cantReplace(let release, let problem):
            heading("Readback \(release.version) is out")
            note(problem.message)
            Button("Download page") { updater.openPage(release) }
                .controlSize(.small)
                .padding(.top, 10)
        case .downloading(let release, let received, let total):
            heading("Downloading \(release.version)")
            Meter(fraction: total > 0 ? Double(received) / Double(total) : nil)
                .padding(.top, 9)
            HStack {
                Text(DownloadAmount.text(received: received, total: total > 0 ? total : nil))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", action: updater.cancel)
                    .buttonStyle(.readback(.quiet))
                    .controlSize(.small)
                    .padding(.trailing, -ControlMetrics.smallQuietPadding)
            }
            .padding(.top, 5)
        case .installing(let release):
            heading("Installing \(release.version)")
            note("Readback will close and reopen in a moment.")
        case .checkFailed(let failure):
            heading("Couldn\u{2019}t check for updates")
            note(failure.message)
            HStack(spacing: 6) {
                Button("Try again", action: updater.check).controlSize(.small)
                Button("Close", action: updater.close).buttonStyle(.readback(.quiet)).controlSize(.small)
            }
            .padding(.top, 10)
        case .installFailed(let release, let failure):
            heading("Couldn\u{2019}t install \(release.version)")
            note(failure.message)
            // Laid out like Available: two buttons side by side didn't fit the sidebar's 180 pt.
            Button(action: updater.install) {
                Text("Try again").frame(maxWidth: .infinity)
            }
                .controlSize(.small)
                .disabled(wait != nil)
                .padding(.top, 10)
            pageLink("Download page", release)
        }
    }

    /// What Install would cut off right now. Read here so the card updates as that work finishes.
    private var wait: UpdateWait? {
        let installing: Bool
        if case .installing = runtime.state { installing = true } else { installing = false }
        return UpdateWait.of(voiceDownload: downloads.active != nil, engineInstall: installing,
                             connecting: connections.rows.values.contains { $0.busy != nil })
    }

    /// "Readback 0.5.0": opens About.
    private var versionLine: some View {
        Button(action: openAbout) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Readback").font(.system(size: 13, weight: .semibold))
                Text(Bundle.main.version).font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("About Readback")
        .accessibilityLabel("About Readback")
        .accessibilityValue(Bundle.main.version)
    }

    // Wrapping text with a line cap, never `fixedSize(vertical:)`: measured while the window
    // works out its smallest size, a fixed-size text claimed a tall column and pushed the whole
    // window's content up and out (seen 2026-11-26; the Voices install bar hit the same, 2026-11-25).
    /// A quiet link to the release's page, right-aligned under the card's main button.
    private func pageLink(_ title: String, _ release: Release) -> some View {
        HStack {
            Spacer()
            Button(title) { updater.openPage(release) }
                .buttonStyle(.readback(.quiet))
                .controlSize(.small)
                .padding(.trailing, -ControlMetrics.smallQuietPadding)
        }
        .padding(.top, 4)
    }

    private func heading(_ text: String) -> some View {
        Text(text).font(.system(size: 12, weight: .semibold)).lineLimit(2)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .lineLimit(5)
            .padding(.top, 2)
    }
}

/// "⟳ Check for updates": quiet until the pointer's on it. While checking, the arrow turns
/// (it keeps turning with Reduce Motion: it's the only sign anything's happening).
private struct CheckLine: View {
    let title: String
    let turning: Bool
    let action: () -> Void
    @State private var hovering = false
    @State private var angle: Double = 0

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .semibold))
                    .rotationEffect(.degrees(angle))
                    .accessibilityHidden(true)
                Text(title).font(.system(size: 12))
            }
            .foregroundStyle(hovering && !turning ? .primary : .secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 3)
        .onHover { hovering = $0 }
        .onAppear { if turning { withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { angle = 360 } } }
        .accessibilityLabel(title)
    }
}
