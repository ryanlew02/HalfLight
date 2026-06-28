//
//  ProgressState.swift
//  HalfLight
//
//  The bundle of per-account progress that doesn't already ride along with the
//  dreams (which sync on their own): the "can't remember" and XP-credit day logs,
//  banked quest XP, claimed-quest records, and the quest seed. Synced to the
//  account as a single `progress_state` JSON blob — mirroring how Lucid Path
//  progress syncs — so signing in on another device restores the same streak,
//  XP and quest board, and signing out leaves nothing behind for the next person.
//

import Foundation

struct ProgressState: Codable, Sendable, Equatable {
    /// Days marked "can't remember" — start-of-day timestamps (seconds since 1970).
    var skippedDays: [Double] = []
    /// Days whose journaling XP must outlive the dream that earned it.
    var creditDays: [Double] = []
    /// Quest XP banked from claimed quests.
    var questBankedXP: Int = 0
    /// Week-scoped ids of quests (and the all-complete bonus) already claimed.
    var questClaimedKeys: [String] = []

    static let empty = ProgressState()

    /// Snapshot the device's current local progress from its backing stores.
    @MainActor
    static func local() -> ProgressState {
        let defaults = UserDefaults.standard
        return ProgressState(
            skippedDays: DayLog.skipped.days().map(\.timeIntervalSince1970),
            creditDays: DayLog.journalCredit.days().map(\.timeIntervalSince1970),
            questBankedXP: defaults.integer(forKey: QuestRewards.bankedXPKey),
            questClaimedKeys: defaults.stringArray(forKey: QuestRewards.claimedKey) ?? []
        )
    }

    /// Merge this (local) state with the account's `remote` one, never losing
    /// progress: union the append-only day logs and claimed keys, keep the higher
    /// banked XP, and let the account's seed win so every device draws the same
    /// board (a fresh account with no seed yet adopts this device's).
    func merged(with remote: ProgressState) -> ProgressState {
        ProgressState(
            skippedDays: Array(Set(skippedDays).union(remote.skippedDays)),
            creditDays: Array(Set(creditDays).union(remote.creditDays)),
            questBankedXP: max(questBankedXP, remote.questBankedXP),
            questClaimedKeys: Array(Set(questClaimedKeys).union(remote.questClaimedKeys))
        )
    }

    /// Write this state into the device's local stores. Callers that cache the day
    /// logs (e.g. `DreamStore`) should refresh afterwards.
    @MainActor
    func applyLocally() {
        let defaults = UserDefaults.standard
        DayLog.skipped.replaceAll(skippedDays.map { Date(timeIntervalSince1970: $0) })
        DayLog.journalCredit.replaceAll(creditDays.map { Date(timeIntervalSince1970: $0) })
        defaults.set(questBankedXP, forKey: QuestRewards.bankedXPKey)
        defaults.set(questClaimedKeys, forKey: QuestRewards.claimedKey)
    }
}
