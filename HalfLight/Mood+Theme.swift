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
        }
    }
}
