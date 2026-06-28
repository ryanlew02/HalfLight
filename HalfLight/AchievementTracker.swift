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
    /// Maps achievement id → the date it was first seen unlocked, so the Home
    /// screen can show the most recent ones.
    private static let unlockDatesKey = "achievementUnlockDates"

    private static func celebratedIDs() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: celebratedKey) ?? [])
    }

    private static func storeCelebrated(_ ids: Set<String>) {
        UserDefaults.standard.set(Array(ids), forKey: celebratedKey)
    }

    private static func unlockDates() -> [String: Date] {
        (UserDefaults.standard.dictionary(forKey: unlockDatesKey) as? [String: Date]) ?? [:]
    }

    private static func storeUnlockDates(_ dates: [String: Date]) {
        UserDefaults.standard.set(dates, forKey: unlockDatesKey)
    }

    /// Record now as the unlock time for any of `ids` not already dated.
    private static func stampUnlocked(_ ids: [String]) {
        var dates = unlockDates()
        let now = Date()
        var changed = false
        for id in ids where dates[id] == nil {
            dates[id] = now
            changed = true
        }
        if changed { storeUnlockDates(dates) }
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
        stampUnlocked(newly.map(\.id))
        return newly
    }

    /// Every achievement ordered for a "recently unlocked" view: unlocked badges
    /// newest-first, then locked badges in catalog order. Badges unlocked before
    /// date tracking existed are backfilled with the time they're first read here;
    /// date ties (e.g. that initial batch) fall back to catalog order, most
    /// advanced first.
    static func sortedByRecency(for stats: AchievementStats) -> [Achievement] {
        let unlocked = Achievement.all.filter { $0.isUnlocked(for: stats) }
        stampUnlocked(unlocked.map(\.id))
        let dates = unlockDates()
        let order = Dictionary(
            uniqueKeysWithValues: Achievement.all.enumerated().map { ($0.element.id, $0.offset) }
        )
        return Achievement.all.sorted { lhs, rhs in
            let lUnlocked = lhs.isUnlocked(for: stats)
            let rUnlocked = rhs.isUnlocked(for: stats)
            if lUnlocked != rUnlocked { return lUnlocked }  // unlocked first

            let lOrder = order[lhs.id] ?? 0
            let rOrder = order[rhs.id] ?? 0
            if lUnlocked {
                let l = dates[lhs.id] ?? .distantPast
                let r = dates[rhs.id] ?? .distantPast
                if l != r { return l > r }
                return lOrder > rOrder  // ties: most advanced first
            }
            return lOrder < rOrder  // both locked: catalog order
        }
    }

    /// The most recently unlocked achievements, newest first, limited to `limit`.
    static func recentlyUnlocked(for stats: AchievementStats, limit: Int) -> [Achievement] {
        Array(sortedByRecency(for: stats).lazy.filter { $0.isUnlocked(for: stats) }.prefix(limit))
    }

    /// Mark every currently-unlocked achievement as already celebrated (without
    /// returning any for a popup). Used to re-baseline after a sign-in pulls the
    /// account's progress in, so the backlog of now-unlocked badges doesn't fire a
    /// burst of popups — only badges earned *after* this point are celebrated.
    static func markAllCelebrated(for stats: AchievementStats) {
        let unlocked = Achievement.all.filter { $0.isUnlocked(for: stats) }
        storeCelebrated(celebratedIDs().union(unlocked.map(\.id)))
        stampUnlocked(unlocked.map(\.id))
        UserDefaults.standard.set(true, forKey: seededKey)
    }

    /// Forget all celebration and unlock-date bookkeeping (used on sign-out so the
    /// next person on this device doesn't inherit unlocked badges). Achievements
    /// re-derive from stats, so a returning account silently re-baselines via
    /// `seedIfNeeded` on its next sign-in.
    static func reset() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: celebratedKey)
        defaults.removeObject(forKey: unlockDatesKey)
        defaults.removeObject(forKey: seededKey)
    }
}
