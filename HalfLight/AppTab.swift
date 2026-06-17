//
//  AppTab.swift
//  HalfLight
//
//  The selectable destinations in the bottom tab bar.
//

import Foundation

enum AppTab: CaseIterable, Identifiable {
    case home
    case lucid
    case journal
    case progress
    case profile

    var id: Self { self }

    var title: String {
        switch self {
        case .home: "Home"
        case .lucid: "Lucid"
        case .journal: "Journal"
        case .progress: "Progress"
        case .profile: "Profile"
        }
    }

    var icon: String {
        switch self {
        case .home: "house.fill"
        case .lucid: "eye.fill"
        case .journal: "book.fill"
        case .progress: "chart.bar.fill"
        case .profile: "person.crop.circle.fill"
        }
    }
}
