import SwiftUI
import AppKit

/// Colors approximating Claude's warm, editorial visual language (terracotta
/// accent on soft neutral surfaces). These are a good-faith approximation for
/// this personal utility, not values pulled from an official design system.
enum ClaudeTheme {
    static let accent = Color(red: 0.80, green: 0.47, blue: 0.34)      // warm terracotta
    static let accentSoft = Color(red: 0.80, green: 0.47, blue: 0.34).opacity(0.16)

    // `surface`/`cardStroke` must track light/dark mode: they previously were
    // fixed to a light cream, which meant .primary/.secondary text (which does
    // adapt) turned near-white-on-near-white in Dark Mode.
    static let surface = adaptiveColor(
        light: NSColor(red: 0.98, green: 0.96, blue: 0.93, alpha: 1),   // warm cream
        dark: NSColor(red: 0.16, green: 0.15, blue: 0.14, alpha: 1)     // warm charcoal
    )
    static let cardStroke = adaptiveColor(
        light: NSColor(red: 0.87, green: 0.83, blue: 0.77, alpha: 1),
        dark: NSColor(red: 0.34, green: 0.32, blue: 0.29, alpha: 1)
    )

    private static func adaptiveColor(light: NSColor, dark: NSColor) -> Color {
        Color(NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }

    static func severityColor(forPercent percent: Int) -> Color {
        switch percent {
        case ..<70: return Color(red: 0.55, green: 0.60, blue: 0.45)   // calm sage
        case 70..<90: return accent
        default: return Color(red: 0.78, green: 0.30, blue: 0.28)      // warning clay red
        }
    }
}
