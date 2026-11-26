import AppKit
import SwiftUI

/// One radius ladder for the whole window, so curves nest: anything inside a card uses the
/// card's radius minus the padding between them, and every corner is continuous.
/// One spacing scale for every page: section gaps, card gaps and card padding come from here,
/// so pages keep the same rhythm. (Owner asked for better spacing, 2026-11-25.)
enum Spacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

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

/// The window's colours: a translucent window with the desktop blurred behind it, the sidebar
/// the more see-through pane and a touch darker, the page mostly solid, and cards a step lighter
/// than what they sit on. The owner chose this (mockup A) on 2026-11-25, reversing the opaque
/// window of 2026-11-24. The tints are tuned so secondary text holds 4.5:1 over a white or a
/// black desktop.
enum WindowColors {
    /// Laid over the blurred desktop (`GlassBackground`).
    static let sidebarTint = Color(nsColor: dynamic(light: 0xE4E4E7, dark: 0x101114, alpha: 0.66))
    static let pageTint = Color(nsColor: dynamic(light: 0xF4F4F5, dark: 0x202126, alpha: 0.84))
    static let page = Color(nsColor: dynamic(light: 0xF4F4F5, dark: 0x1D1E22))
    static let sidebar = Color(nsColor: dynamic(light: 0xEAEAEC, dark: 0x2A2C31))
    /// Cards, hovers and highlights are a light overlay rather than a solid colour, so on the
    /// glass they stay a step above whatever shows through (a solid dark card read as a hole).
    static let card = overlay(light: (1, 0.72), dark: (1, 0.06))
    static let cardHover = overlay(light: (1, 0.9), dark: (1, 0.09))
    /// A card that's playing or chosen: a neutral tint a step above a resting card (no accent:
    /// the owner's black-and-white look, 2026-11-25; my call to keep it a tint, not a solid plate).
    static let cardActive = overlay(light: (0, 0.07), dark: (1, 0.12))
    /// Sidebar cards and the highlight sit on the sidebar, so they're a step lighter than it.
    static let sidebarCard = overlay(light: (1, 0.55), dark: (1, 0.06))
    static let rowHighlight = overlay(light: (0, 0.05), dark: (1, 0.07))
    static let rowSelected = overlay(light: (0, 0.08), dark: (1, 0.11))
    /// A hairline that separates rows inside a card.
    static let hairline = overlay(light: (0, 0.07), dark: (1, 0.07))

    /// White (1) or black (0) at an opacity, per appearance.
    private static func overlay(light: (white: CGFloat, alpha: CGFloat), dark: (white: CGFloat, alpha: CGFloat)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let pick = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(white: pick.white, alpha: pick.alpha)
        })
    }

    private static func dynamic(light: UInt32, dark: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? rgb(dark, alpha) : rgb(light, alpha)
        }
    }

    private static func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
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
            VStack(alignment: .leading, spacing: Spacing.xl) {
                ForEach(sections: configuration.content) { section in
                    VStack(alignment: .leading, spacing: Spacing.s) {
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
                                    WindowColors.hairline.frame(height: 1).padding(.leading, Spacing.l)
                                }
                                row
                                    // Tall enough for a full-size control, so a row with a switch and a row with
                                    // a dropdown are the same height.
                                    .frame(maxWidth: .infinity, minHeight: ControlMetrics.height, alignment: .leading)
                                    .padding(.horizontal, Spacing.l)
                                    .padding(.vertical, 10)   // 34 + 10 + 10: 54 pt rows
                            }
                        }
                        .surface()
                        if !section.footer.isEmpty {
                            section.footer.padding(.horizontal, 4)
                        }
                    }
                }
            }
            .padding(.horizontal, PageMetrics.inset)
            .padding(.top, Spacing.s)
            .padding(.bottom, PageMetrics.inset)
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
            ReadbackSwitch(isOn: configuration.$isOn)
        }
        // One element for VoiceOver: the row's words, read as a switch with its state.
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(configuration.isOn ? "on" : "off")
        .accessibilityAction { configuration.isOn.toggle() }
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
