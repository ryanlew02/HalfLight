//
//  AppTab.swift
//  HalfLight
//
//  The selectable destinations in the bottom tab bar.
//

import Foundation

enum AppTab: CaseIterable, Identifiable {
    case home
    case journal
    case lucid
    case feed
    case profile

    var id: Self { self }

    var title: String {
        switch self {
        case .home: "Home"
        case .lucid: "Lucid"
        case .journal: "Journal"
        case .feed: "Feed"
        case .profile: "Profile"
        }
    }

    var icon: String {
        switch self {
        case .home: "house.fill"
        case .lucid: "eye.fill"
        case .journal: "book.fill"
        case .feed: "person.2.fill"
        case .profile: "person.crop.circle.fill"
        }
    }
}
