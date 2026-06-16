//
//  SkippedDayStore.swift
//  HalfLight
//
//  Persists the days the user tapped "I'm not sure" on the home prompt. These
//  count as journaled days in the Stats activity grid even though no dream was
//  recorded. Stored as start-of-day timestamps in UserDefaults.
//

import Foundation

enum SkippedDayStore {
    private static let key = "dreamSkippedDays"

    /// All days the user has marked as "can't remember", normalized to start-of-day.
    static func days() -> Set<Date> {
        let timestamps = UserDefaults.standard.array(forKey: key) as? [Double] ?? []
        return Set(timestamps.map { Date(timeIntervalSince1970: $0) })
    }

    /// Record `date`'s calendar day as skipped. No-op if already recorded.
    static func record(_ date: Date) {
        let day = Calendar.current.startOfDay(for: date).timeIntervalSince1970
        var timestamps = UserDefaults.standard.array(forKey: key) as? [Double] ?? []
        guard !timestamps.contains(day) else { return }
        timestamps.append(day)
        UserDefaults.standard.set(timestamps, forKey: key)
    }
}
