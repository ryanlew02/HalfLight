//
//  HalfLightShortcuts.swift
//  HalfLight
//
//  Exposes the quick-capture intent to Siri and Spotlight so "Record a dream in
//  HalfLight" works hands-free — handy the moment you wake. App target only
//  (an AppShortcutsProvider must be registered by exactly one target).
//

import AppIntents

struct HalfLightShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: QuickRecordIntent(),
            phrases: [
                "Record a dream in \(.applicationName)",
                "Log a dream in \(.applicationName)",
                "New dream in \(.applicationName)"
            ],
            shortTitle: "Record a Dream",
            systemImageName: "mic.fill"
        )
    }
}
