//
//  Mood+Theme.swift
//  HalfLight
//
//  Visual theming for dream moods.
//

import SwiftUI

extension Dream.Mood {
    /// The accent color associated with this mood.
    var tint: Color {
        switch self {
        case .peaceful: Color(red: 0.40, green: 0.62, blue: 0.92)
        case .joyful:   Color(red: 0.98, green: 0.78, blue: 0.34)
        case .strange:  Color(red: 0.70, green: 0.50, blue: 0.92)
        case .anxious:  Color(red: 0.55, green: 0.62, blue: 0.70)
        case .vivid:    Color(red: 0.95, green: 0.45, blue: 0.70)
        case .nightmare: Color(red: 0.42, green: 0.30, blue: 0.55)
        case .romantic: Color(red: 0.95, green: 0.40, blue: 0.55)
        case .sad:      Color(red: 0.40, green: 0.50, blue: 0.62)
        case .exciting: Color(red: 0.98, green: 0.55, blue: 0.25)
        case .mysterious: Color(red: 0.32, green: 0.36, blue: 0.64)
        case .lonely:   Color(red: 0.50, green: 0.55, blue: 0.60)
        case .hopeful:  Color(red: 0.98, green: 0.68, blue: 0.50)
        case .nostalgic: Color(red: 0.80, green: 0.60, blue: 0.40)
        case .euphoric: Color(red: 0.85, green: 0.35, blue: 0.85)
        }
    }
}
