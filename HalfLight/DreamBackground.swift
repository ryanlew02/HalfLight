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

struct DreamBackground: View {
    var body: some View {
        LinearGradient(
            colors: [.dreamBase, .dreamSurface],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
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
