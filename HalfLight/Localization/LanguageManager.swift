//
//  LanguageManager.swift
//  HalfLight
//
//  In-app language selection. HalfLight ships in 12 languages and lets the
//  dreamer switch between them from Settings — live, without relaunching.
//
//  How the live switch works: iOS resolves `Text("…")` / `String(localized:)`
//  through `Bundle.main` at lookup time, but it normally only reads the language
//  chosen at launch. We swap `Bundle.main`'s class for `PrivateBundle`, which
//  redirects every localized lookup to the `.lproj` of the chosen language. When
//  the choice changes we re-point that bundle and re-render the view tree (see
//  `HalfLightApp`), so all on-screen strings update immediately.
//

import Foundation
import SwiftUI

/// The languages HalfLight is translated into. Raw value is the `.lproj` / BCP-47
/// code used by the bundle and the String Catalog.
enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case spanish = "es"
    case french = "fr"
    case german = "de"
    case italian = "it"
    case portugueseBrazil = "pt-BR"
    case dutch = "nl"
    case russian = "ru"
    case japanese = "ja"
    case korean = "ko"
    case chineseSimplified = "zh-Hans"
    case arabic = "ar"

    var id: String { rawValue }

    /// The `.lproj` resource name / BCP-47 identifier.
    var code: String { rawValue }

    /// The language's name written in itself — what we show in the picker.
    var nativeName: String {
        switch self {
        case .english: "English"
        case .spanish: "Español"
        case .french: "Français"
        case .german: "Deutsch"
        case .italian: "Italiano"
        case .portugueseBrazil: "Português (Brasil)"
        case .dutch: "Nederlands"
        case .russian: "Русский"
        case .japanese: "日本語"
        case .korean: "한국어"
        case .chineseSimplified: "简体中文"
        case .arabic: "العربية"
        }
    }

    var locale: Locale { Locale(identifier: rawValue) }

    /// Arabic reads right-to-left; everything else is left-to-right.
    var isRTL: Bool { self == .arabic }
}

/// Owns the dreamer's chosen language: persists it, points the localized bundle
/// at it, and publishes changes so the UI can re-render live.
@Observable
final class LanguageManager {
    static let shared = LanguageManager()

    private static let storageKey = "selectedAppLanguage"

    /// The active language. Setting it re-points the localized bundle and saves
    /// the choice; the view tree re-renders because `current` is observed.
    var current: AppLanguage {
        didSet {
            guard current != oldValue else { return }
            apply()
        }
    }

    private init() {
        let stored = UserDefaults.standard.string(forKey: Self.storageKey)
        current = stored.flatMap(AppLanguage.init(rawValue:)) ?? Self.systemDefault()
        // Point the bundle at the initial language before the first frame renders.
        Bundle.setAppLanguage(current.code)
    }

    private func apply() {
        Bundle.setAppLanguage(current.code)
        UserDefaults.standard.set(current.code, forKey: Self.storageKey)
        // Mirror to AppleLanguages so system-provided UI (date pickers, share
        // sheets) and a future relaunch agree with our in-app choice.
        UserDefaults.standard.set([current.code], forKey: "AppleLanguages")
    }

    /// Best match for the device's preferred languages, falling back to English.
    private static func systemDefault() -> AppLanguage {
        for preferred in Locale.preferredLanguages {
            let lower = preferred.lowercased()
            // Region/script-specific match first (e.g. "pt-BR", "zh-Hans-CN").
            if let exact = AppLanguage.allCases.first(where: { lower.hasPrefix($0.code.lowercased()) }) {
                return exact
            }
            // Then the base language (e.g. "es-MX" → Spanish, "zh-Hant" → none).
            let base = String(lower.prefix(2))
            if let match = AppLanguage.allCases.first(where: { $0.code.lowercased().hasPrefix(base) }) {
                return match
            }
        }
        return .english
    }
}

// MARK: - Live string lookup

/// Localizes `key` through the (swizzled) main bundle so the result tracks the
/// in-app language and updates the moment it changes.
///
/// Use this for plain `String` values — greetings, enum labels, names pulled
/// from data — that are *not* rendered directly as a SwiftUI `Text`. Don't reach
/// for `String(localized:)` here: that API resolves against the bundle's
/// launch-time localization and ignores our runtime bundle override, so those
/// strings would freeze on whatever language was shown first. `Text("…")` /
/// `LocalizedStringKey` already route through the override and need no help.
func localized(_ key: String) -> String {
    Bundle.main.localizedString(forKey: key, value: key, table: nil)
}

/// Format-string variant: looks up `key` (e.g. `"%lld dreams remembered"`),
/// then substitutes the arguments into the translated format.
func localized(_ key: String, _ arguments: CVarArg...) -> String {
    let format = Bundle.main.localizedString(forKey: key, value: key, table: nil)
    return arguments.isEmpty ? format : String(format: format, arguments: arguments)
}

// MARK: - Bundle override

/// Address used to stash the chosen-language bundle on `Bundle.main` via the
/// Objective-C associated-objects runtime. `nonisolated(unsafe)` because we only
/// touch it from the main thread during a language change.
private nonisolated(unsafe) var localizedBundleKey: UInt8 = 0

/// Stand-in for `Bundle.main` that resolves localized strings against the
/// currently-selected language's `.lproj` instead of the launch language.
private final class PrivateBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let bundle = objc_getAssociatedObject(self, &localizedBundleKey) as? Bundle {
            return bundle.localizedString(forKey: key, value: value, table: tableName)
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}

extension Bundle {
    /// Swaps `Bundle.main`'s class exactly once so localized lookups can be
    /// redirected at runtime.
    private static let swizzleOnce: Void = {
        object_setClass(Bundle.main, PrivateBundle.self)
    }()

    /// Points `Bundle.main`'s localized lookups at the given language's `.lproj`.
    static func setAppLanguage(_ code: String) {
        _ = swizzleOnce
        let bundle = Bundle.main.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:))
        objc_setAssociatedObject(Bundle.main, &localizedBundleKey, bundle, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}
