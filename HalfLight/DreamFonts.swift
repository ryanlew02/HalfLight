//
//  DreamFonts.swift
//  HalfLight
//
//  The three-typeface system for the editorial / celestial redesign:
//    • Instrument Serif — display & titles (the serif carries the weight)
//    • Space Grotesk    — UI & running body copy
//    • JetBrains Mono   — eyebrow labels, dates, metadata, dot-meters
//
//  The TTFs are bundled and registered at launch (no Info.plist `UIAppFonts`
//  entry required). Until the files are added to the target, every helper falls
//  back to the closest system design (`.serif` / `.monospaced` / default), so the
//  layout is correct immediately and simply sharpens once the fonts are present.
//

import SwiftUI
import CoreText
#if canImport(UIKit)
import UIKit
#endif

enum DreamFonts {
    // PostScript names of the bundled faces (match the Google Fonts TTFs).
    static let serifRegular   = "InstrumentSerif-Regular"
    static let serifItalic    = "InstrumentSerif-Italic"
    static let groteskRegular = "SpaceGrotesk-Regular"
    static let groteskMedium  = "SpaceGrotesk-Medium"
    static let groteskSemiBold = "SpaceGrotesk-SemiBold"
    static let groteskBold    = "SpaceGrotesk-Bold"
    static let monoRegular    = "JetBrainsMono-Regular"
    static let monoMedium     = "JetBrainsMono-Medium"
    static let monoSemiBold   = "JetBrainsMono-SemiBold"

    /// Register every `.ttf` bundled with the app so `Font.custom(...)` resolves
    /// without an Info.plist entry. Safe to call once at launch; a no-op if no
    /// fonts are bundled yet (the helpers then fall back to system faces).
    static func registerBundled() {
        #if canImport(UIKit)
        for ext in ["ttf", "otf"] {
            guard let urls = Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) else { continue }
            for url in urls {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
        availabilityCache.removeAll()
        #endif
    }

    /// Whether a named font is actually installed, memoized. Drives the fallback
    /// decision in the `Font` helpers below.
    private static var availabilityCache: [String: Bool] = [:]
    static func isAvailable(_ name: String) -> Bool {
        if let cached = availabilityCache[name] { return cached }
        #if canImport(UIKit)
        let available = UIFont(name: name, size: 12) != nil
        #else
        let available = false
        #endif
        availabilityCache[name] = available
        return available
    }
}

extension Font {
    /// Instrument Serif — display & titles. Regular weight only (the serif's
    /// forms carry the emphasis); pass `italic` for the accent variant.
    static func dreamSerif(_ size: CGFloat, italic: Bool = false) -> Font {
        let name = italic ? DreamFonts.serifItalic : DreamFonts.serifRegular
        if DreamFonts.isAvailable(name) {
            return .custom(name, size: size)
        }
        let system = Font.system(size: size, weight: .regular, design: .serif)
        return italic ? system.italic() : system
    }

    /// Space Grotesk — UI & body copy. The weight selects the matching cut.
    static func dreamGrotesk(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .bold, .heavy, .black: name = DreamFonts.groteskBold
        case .semibold:             name = DreamFonts.groteskSemiBold
        case .medium:               name = DreamFonts.groteskMedium
        default:                    name = DreamFonts.groteskRegular
        }
        if DreamFonts.isAvailable(name) {
            return .custom(name, size: size)
        }
        return .system(size: size, weight: weight, design: .default)
    }

    /// JetBrains Mono — labels, dates, metadata, dot-meters.
    static func dreamMono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .semibold, .bold, .heavy, .black: name = DreamFonts.monoSemiBold
        case .medium:                          name = DreamFonts.monoMedium
        default:                               name = DreamFonts.monoRegular
        }
        if DreamFonts.isAvailable(name) {
            return .custom(name, size: size)
        }
        return .system(size: size, weight: weight, design: .monospaced)
    }
}
