import SwiftUI

/// The window's motion: quick springs that settle fast with a little overshoot, and a plain
/// short fade instead when the person has Reduce Motion on. The owner asked for expressive,
/// polished motion on 2026-11-25.
enum Motion {
    /// How far a control sinks while pressed.
    static let press: CGFloat = 0.97

    static func spring(_ reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.72)
    }

    /// For anything that changes a layout's height (a card arriving, a stack or a section opening):
    /// settles with no overshoot, so the content below never wobbles. The bounce stays on small
    /// things that don't push others around (a press, a switch's thumb). Design review, 2026-11-25.
    static func reveal(_ reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 1)
    }

    /// For things that pop in or open (menus, chips): a touch more bounce.
    static func pop(_ reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.32, dampingFraction: 0.62)
    }
}
