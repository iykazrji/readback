import AppKit
import SwiftUI

/// The desktop, blurred, behind a pane of the main window, under a tint of the pane's colour.
/// SwiftUI's own materials only blur what's inside the window; this one blurs what's behind it.
/// The owner chose this look (mockup A: a glassy, darker sidebar and a calmer page) on 2026-11-25.
struct GlassBackground: View {
    let material: NSVisualEffectView.Material
    let tint: Color

    init(_ material: NSVisualEffectView.Material, tint: Color) {
        self.material = material
        self.tint = tint
    }

    var body: some View {
        ZStack {
            BehindWindowBlur(material: material)
            tint
        }
        .accessibilityHidden(true)
    }
}

private struct BehindWindowBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        // Stays frosted when the window isn't in front, like Finder's sidebar, rather than going flat grey.
        view.state = .active
        view.material = material
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}
