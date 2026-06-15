//
//  DreamBackground.swift
//  HalfLight
//
//  Shared dreamy gradient backdrop and the app color palette.
//

import SwiftUI

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
    static let dreamBase = Color(hex: 0x14132B)
    /// Raised surface (cards, sheets).
    static let dreamSurface = Color(hex: 0x211F3D)
    /// Primary brand accent — warm amber. Used for key interactive elements.
    static let dreamPrimary = Color(hex: 0xE8A95C)
    /// Secondary accent — terracotta. Used for highlights and gradients.
    static let dreamAccent = Color(hex: 0xD98B6B)
    /// Default text color — warm cream.
    static let dreamText = Color(hex: 0xF4ECDD)

    /// Create a color from a 0xRRGGBB integer.
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
