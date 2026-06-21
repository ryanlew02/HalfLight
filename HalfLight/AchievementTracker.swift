//
//  AchievementTracker.swift
//  HalfLight
//
//  Remembers which achievements have already been celebrated with a full-screen
//  popup, so each badge fires exactly once the moment it's unlocked. Achievements
//  themselves stay stateless (recomputed from the library); this is the thin layer
//  of persistence that turns "currently unlocked" into "newly unlocked".
//

import Foundation

enum AchievementTracker {
    /// IDs of every achievement we've already shown a popup for.
    private static let celebratedKey = "celebratedAchievements"
    /// Set once the baseline has been recorded, so existing dreamers aren't flooded.
    private static let seededKey = "achievementsSeeded"

    private static func celebratedIDs() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: celebratedKey) ?? [])
    }

    private static func storeCelebrated(_ ids: Set<String>) {
        UserDefaults.standard.set(Array(ids), forKey: celebratedKey)
    }

    /// One-time baseline: records everything already unlocked as "celebrated" so a
    /// dreamer who earned badges before this feature existed doesn't get a burst of
    /// popups on first launch. Safe to call on every launch — it only acts once.
    static func seedIfNeeded(for stats: AchievementStats) {
        guard !UserDefaults.standard.bool(forKey: seededKey) else { return }
        let unlocked = Achievement.all.filter { $0.isUnlocked(for: stats) }
        storeCelebrated(Set(unlocked.map(\.id)))
        UserDefaults.standard.set(true, forKey: seededKey)
    }

    /// Achievements unlocked since the last check, in display order, each marked
    /// celebrated so it's only ever returned once. Returns nothing until the
    /// baseline has been seeded (seeding it on the spot if needed).
    static func newlyUnlocked(for stats: AchievementStats) -> [Achievement] {
        guard UserDefaults.standard.bool(forKey: seededKey) else {
            seedIfNeeded(for: stats)
            return []
        }
        let celebrated = celebratedIDs()
        let newly = Achievement.all.filter {
            $0.isUnlocked(for: stats) && !celebrated.contains($0.id)
        }
        guard !newly.isEmpty else { return [] }
        storeCelebrated(celebrated.union(newly.map(\.id)))
        return newly
    }
}
