//
//  DayLog.swift
//  HalfLight
//
//  A persistent, append-only set of calendar days backed by UserDefaults, stored
//  as start-of-day timestamps. Two logs share the type: the "can't remember" days
//  shown in the Stats grid, and the journaling-XP credit log that lets a day's XP
//  survive deleting the dream that earned it.
//

import Foundation

struct DayLog {
    let key: String

    /// Days the user tapped "I'm not sure" on the home prompt. These count as
    /// journaled days in the Stats activity grid even though no dream was recorded.
    static let skipped = DayLog(key: "dreamSkippedDays")

    /// Days that have already earned the once-per-day journaling XP. Append-only:
    /// recorded when a dream is deleted so the day's XP is never lost, and deduped
    /// against live dream/skip days so a day can only ever be worth one credit.
    static let journalCredit = DayLog(key: "journalCreditDays")

    /// All recorded days, normalized to start-of-day.
    func days() -> Set<Date> {
        let timestamps = UserDefaults.standard.array(forKey: key) as? [Double] ?? []
        return Set(timestamps.map { Date(timeIntervalSince1970: $0) })
    }

    /// Record `date`'s calendar day. No-op if already recorded.
    func record(_ date: Date) {
        let day = Calendar.current.startOfDay(for: date).timeIntervalSince1970
        var timestamps = UserDefaults.standard.array(forKey: key) as? [Double] ?? []
        guard !timestamps.contains(day) else { return }
        timestamps.append(day)
        UserDefaults.standard.set(timestamps, forKey: key)
    }

    /// Replace the log with exactly `dates` (used when pulling the account's days
    /// down on sign-in so the device mirrors the account).
    func replaceAll(_ dates: some Sequence<Date>) {
        let timestamps = Set(dates.map { Calendar.current.startOfDay(for: $0).timeIntervalSince1970 })
        UserDefaults.standard.set(Array(timestamps), forKey: key)
    }

    /// Forget every recorded day (used on sign-out so the streak, journaled-day
    /// count and journaling XP don't outlive the account that earned them).
    func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
