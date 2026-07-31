//
//  WidgetTheme.swift
//  HalfLightWidgets
//
//  A small, self-contained slice of the app's visual language for the widget
//  extension (which can't see the app target's color tokens). Keep the hexes in
//  step with DreamBackground.swift in the app.
//

import SwiftUI

extension Color {
    /// Create a color from a 0xRRGGBB integer.
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    /// An adaptive color resolving to `light` or `dark` for the active appearance.
    init(light: UInt32, dark: UInt32) {
        #if canImport(UIKit)
        self.init(uiColor: UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
        })
        #else
        self.init(hex: light)
        #endif
    }

    static let dreamBase = Color(light: 0xFAF3E8, dark: 0x14132B)
    static let dreamBaseDeep = Color(light: 0xF3E7D3, dark: 0x100E22)
    static let dreamAccent = Color(light: 0xB6A6CE, dark: 0xD98B6B)
    static let dreamSurface = Color(light: 0xFFFFFF, dark: 0x211F3D)
    static let dreamPrimary = Color(light: 0xE8A598, dark: 0xE8A95C)
    static let dreamText = Color(light: 0x3A3228, dark: 0xF4ECDD)
    static let dreamSubtle = Color(light: 0x7A7160, dark: 0xA99F8C)
    static let dreamOnPrimary = Color(light: 0x3A3228, dark: 0x2E2008)
}

/// Rotating lucid-dreaming nudges for the prompt widget. Picked by day so the
/// prompt is stable for a given date but varies morning to morning.
enum DreamPrompts {
    static let all: [String] = [
        "Did you dream last night? Capture it before it fades.",
        "What was the strongest feeling in last night's dream?",
        "Reality check: are you dreaming right now?",
        "Recall one detail from last night — a place, a face, a color.",
        "Set your intention: \u{201C}Tonight I'll know I'm dreaming.\u{201D}",
        "Were you flying, falling, or running? Write it down.",
        "Who appeared in your dream last night?",
        "Notice your dream signs — the recurring oddities.",
        "What would you do if you knew you were dreaming?",
        "A dream a day keeps the haze away. Log today's."
    ]

    /// Today's prompt, stable for the calendar day, in the device language.
    ///
    /// The English text in `all` doubles as the String Catalog key, so a prompt
    /// is looked up rather than shown verbatim — otherwise every locale would
    /// get the English copy.
    static func today(_ date: Date = .now) -> String {
        let day = Calendar.current.ordinality(of: .day, in: .era, for: date) ?? 0
        return String(localized: String.LocalizationValue(all[day % all.count]))
    }
}

extension DreamSnapshot {
    /// Placeholder data for previews and the widget gallery.
    static let sample = DreamSnapshot(
        currentStreak: 5,
        longestStreak: 12,
        totalDreams: 47,
        lucidCount: 8,
        weekCount: 4,
        lastDreamTitle: "The Floating Library",
        lastDreamMood: "Vivid",
        lastDreamMoodSymbol: "wand.and.stars",
        lastDreamMoodColor: 0xF273B3,
        lastDreamDate: .now.addingTimeInterval(-60 * 60 * 8)
    )
}
