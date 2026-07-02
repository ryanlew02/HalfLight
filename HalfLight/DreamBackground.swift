//
//  DreamBackground.swift
//  HalfLight
//
//  Shared dreamy gradient backdrop and the app color palette.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Shared app backdrop. Renders the atmospheric night sky so every screen
/// shares one cohesive background.
struct DreamBackground: View {
    var body: some View {
        NightSkyBackground()
    }
}

extension Color {
    /// Deepest background tone.
    static let dreamBase = Color(light: 0xFAF3E8, dark: 0x14132B)
    /// Raised surface (cards, sheets).
    static let dreamSurface = Color(light: 0xFFFFFF, dark: 0x211F3D)
    /// Primary brand accent. Used for key interactive elements.
    static let dreamPrimary = Color(light: 0xE8A598, dark: 0xE8A95C)
    /// Secondary accent. Used for highlights and gradients.
    static let dreamAccent = Color(light: 0xB6A6CE, dark: 0xD98B6B)
    /// Default text color.
    static let dreamText = Color(light: 0x3A3228, dark: 0xF4ECDD)

    // MARK: Redesign tokens (editorial / celestial system)

    /// Deepest base tone at the bottom of the screen gradient.
    static let dreamBaseDeep = Color(light: 0xF3E7D3, dark: 0x100E22)
    /// Mono eyebrow / metadata labels — warm and recessive.
    static let dreamFaint = Color(light: 0xA89F8A, dark: 0x6C6552)
    /// Secondary running body copy (dream excerpts, sublines).
    static let dreamSubtle = Color(light: 0x7A7160, dark: 0xA99F8C)
    /// The greeting's italic name accent (lavender in light, terracotta in dark).
    static let dreamNameAccent = Color(light: 0x9D86C4, dark: 0xD98B6B)
    /// Foreground used on a solid `dreamPrimary` fill.
    static let dreamOnPrimary = Color(light: 0x3A3228, dark: 0x2E2008)

    /// The moonlit rim on card outlines — the tone the top edge of a surface
    /// takes where it catches the sky's glow (blush by day, pale gold by night).
    static let dreamMoonRim = Color(light: 0xD99A85, dark: 0xF0C98F)
    /// Card shadow tone — warm umber in light mode, deep night indigo in dark —
    /// so depth feels atmospheric instead of neutral black.
    static let dreamCardShadow = Color(light: 0x50402E, dark: 0x060512)

    // Capture CTA / "Surprise me" pill — a high-contrast fill that inverts
    // between modes (dark brown on light, amber on dark).
    static let dreamCTAFill = Color(light: 0x3A3228, dark: 0xE8A95C)
    static let dreamOnCTA = Color(light: 0xFAF3E8, dark: 0x2E2008)
    static let dreamOnCTASub = Color(light: 0xB3A892, dark: 0x5C4519)
    static let dreamCTAGlyph = Color(light: 0xE8A598, dark: 0x2E2008)

    /// Create a color from a 0xRRGGBB integer.
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    /// An adaptive color that resolves to `light` or `dark` based on the active color scheme.
    init(light: UInt32, dark: UInt32) {
        #if canImport(UIKit)
        self.init(uiColor: UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
        })
        #elseif canImport(AppKit)
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(Color(hex: isDark ? dark : light))
        })
        #else
        self.init(hex: dark)
        #endif
    }
}
