//
//  AppTab.swift
//  HalfLight
//
//  The selectable destinations in the bottom tab bar (the center "+" is an
//  action, not a tab, so it is intentionally absent here).
//

import Foundation

enum AppTab: CaseIterable, Identifiable {
    case home
    case journal
    case lucid
    case stats

    var id: Self { self }

    var title: String {
        switch self {
        case .home: "Home"
        case .journal: "Journal"
        case .lucid: "Lucid"
        case .stats: "Profile"
        }
    }

    var icon: String {
        switch self {
        case .home: "house.fill"
        case .journal: "book.fill"
        case .lucid: "moon.stars.fill"
        case .stats: "person.crop.circle.fill"
        }
    }
}
