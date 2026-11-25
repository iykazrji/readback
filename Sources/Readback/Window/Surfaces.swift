import AppKit
import SwiftUI

/// One radius ladder for the whole window, so curves nest: anything inside a card uses the
/// card's radius minus the padding between them, and every corner is continuous.
enum Radius {
    /// Page cards: the stats, replies, notices, settings groups.
    static let card: CGFloat = 16
    /// The sidebar's bottom cards, which sit 10 pt in from the sidebar's edge.
    static let sidebarCard: CGFloat = 12
    /// Sidebar rows and their hover and selected fills.
    static let row: CGFloat = 9
    /// Small controls inside a card (a 24 pt button 8 pt in from a card's corner).
    static let control: CGFloat = 8
    /// The 28 pt tool tiles.
    static let tile: CGFloat = 8
    /// The 22 pt icon tiles in the sidebar.
    static let iconTile: CGFloat = 6
}

/// The window's colours, after superwhisper: an opaque window, a sidebar a step lighter than
/// the page, and cards a step lighter than what they sit on. No translucency, no glass: the
/// owner found the see-through window too busy (2026-11-24).
enum WindowColors {
    static let page = Color(nsColor: dynamic(light: 0xF4F4F5, dark: 0x1D1E22))
    static let sidebar = Color(nsColor: dynamic(light: 0xEAEAEC, dark: 0x2A2C31))
    static let card = Color(nsColor: dynamic(light: 0xFFFFFF, dark: 0x28292E))
    static let cardHover = Color(nsColor: dynamic(light: 0xFAFAFB, dark: 0x2F3036))
    /// A card that's playing or chosen: the accent, lightly.
    static let cardActive = Color(nsColor: dynamic(light: 0xE9F0FE, dark: 0x27324A))
    /// Sidebar cards and the highlight sit on the sidebar, so they're a step lighter than it.
    static let sidebarCard = Color(nsColor: dynamic(light: 0xF7F7F8, dark: 0x34363C))
    static let rowHighlight = Color(nsColor: dynamic(light: 0xDCDCE0, dark: 0x393B42))
    static let rowSelected = Color(nsColor: dynamic(light: 0xD4D5DA, dark: 0x41434B))
    /// A hairline that separates rows inside a card.
    static let hairline = Color(nsColor: dynamic(light: 0xE4E4E7, dark: 0x33343A))

    static let pageNS = dynamic(light: 0xF4F4F5, dark: 0x1D1E22)

    private static func dynamic(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? rgb(dark) : rgb(light)
        }
    }

    private static func rgb(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// How strongly a surface stands out: resting, under the pointer, or the one that's playing.
enum SurfaceEmphasis {
    case resting, hovered, active
}

extension View {
    /// A card: a solid fill a step lighter than the page, in the ladder's shape.
    func surface(radius: CGFloat = Radius.card, emphasis: SurfaceEmphasis = .resting, on base: SurfaceBase = .page) -> some View {
        background(fill(emphasis, base), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    private func fill(_ emphasis: SurfaceEmphasis, _ base: SurfaceBase) -> Color {
        switch (emphasis, base) {
        case (.active, _): return WindowColors.cardActive
        case (.hovered, .page): return WindowColors.cardHover
        case (.resting, .page): return WindowColors.card
        case (.hovered, .sidebar): return WindowColors.rowHighlight
        case (.resting, .sidebar): return WindowColors.sidebarCard
        }
    }
}

/// What a surface sits on, so it's always one step lighter than its background.
enum SurfaceBase { case page, sidebar }

/// Draws a Form's sections as the window's cards (the ladder's radius, the page's card colour,
/// hairlines between rows) instead of the system's grouped sections, whose own radius and
/// fill didn't match the rest of the window. Headers sit above a card, footers below it.
struct CardFormStyle: FormStyle {
    func makeBody(configuration: Configuration) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ForEach(sections: configuration.content) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        if !section.header.isEmpty {
                            section.header
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.primary)
                                .padding(.leading, 4)
                                .accessibilityAddTraits(.isHeader)
                        }
                        VStack(spacing: 0) {
                            ForEach(Array(section.content.enumerated()), id: \.element.id) { index, row in
                                if index > 0 {
                                    WindowColors.hairline.frame(height: 1).padding(.leading, 14)
                                }
                                row
                                    .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                            }
                        }
                        .surface()
                        if !section.footer.isEmpty {
                            section.footer.padding(.horizontal, 4)
                        }
                    }
                }
            }
            .padding(PageMetrics.inset)
            .toggleStyle(SpreadSwitchStyle())
            .labeledContentStyle(SpreadLabeledContentStyle())
        }
    }
}

/// A switch with its label on the left and the switch at the row's right edge, as the system
/// form lays it out.
struct SpreadSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) { configuration.label }
            Spacer(minLength: 8)
            Toggle("", isOn: configuration.$isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
        }
    }
}

/// A label on the left and its value or control at the row's right edge.
struct SpreadLabeledContentStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) { configuration.label }
            Spacer(minLength: 8)
            configuration.content
        }
    }
}
