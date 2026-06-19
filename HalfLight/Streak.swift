//
//  Streak.swift
//  HalfLight
//
//  Current and longest runs of consecutive journaled days, derived from the same
//  day set the Stats activity grid uses (a dream recorded, or the day marked
//  "can't remember"). Shared by Home, the Progress screen, and achievements.
//

import Foundation

struct Streak: Equatable {
    /// The run of days ending today — or yesterday, so an as-yet-unjournaled
    /// today doesn't appear to break a live streak before the day is over.
    let current: Int
    /// The longest run of consecutive journaled days ever recorded.
    let longest: Int

    static let none = Streak(current: 0, longest: 0)

    /// Compute both streaks from a set of journaled calendar days.
    static func from(journaledDays days: Set<Date>, now: Date = .now) -> Streak {
        let calendar = Calendar.current
        let normalized = Set(days.map { calendar.startOfDay(for: $0) })
        guard !normalized.isEmpty else { return .none }

        // Longest run anywhere in the history.
        let sorted = normalized.sorted()
        var longest = 1
        var run = 1
        for (previous, day) in zip(sorted, sorted.dropFirst()) {
            if let next = calendar.date(byAdding: .day, value: 1, to: previous),
               calendar.isDate(next, inSameDayAs: day) {
                run += 1
                longest = max(longest, run)
            } else {
                run = 1
            }
        }

        // Current run, anchored to today (or yesterday during the grace window).
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let anchor: Date
        if normalized.contains(today) {
            anchor = today
        } else if normalized.contains(yesterday) {
            anchor = yesterday
        } else {
            return Streak(current: 0, longest: longest)
        }

        var current = 0
        var cursor = anchor
        while normalized.contains(cursor) {
            current += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor)!
        }
        return Streak(current: current, longest: max(longest, current))
    }
}
