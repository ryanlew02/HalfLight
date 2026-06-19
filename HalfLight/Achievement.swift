//
//  Achievement.swift
//  HalfLight
//
//  The badge / achievement model shown on the Progress screen. Achievements are
//  pure functions of data the app already tracks (recorded dreams, journaling
//  streaks, moods, AI analyses, lucid lessons), so nothing extra is persisted —
//  unlock state is recomputed from the dream library on each appearance.
//

import SwiftUI

/// A snapshot of the metrics every achievement is evaluated against. Built once
/// per render from the dream library and progression state, then handed to each
/// achievement's `measure` closure.
struct AchievementStats {
    /// Total dreams recorded.
    let dreamCount: Int
    /// Dreams that have an AI interpretation attached.
    let analyzedCount: Int
    /// Number of distinct moods used across all dreams.
    let distinctMoods: Int
    /// Number of distinct themes/tags collected across all dreams.
    let distinctTags: Int
    /// Completed lucid-dreaming lessons.
    let lucidSections: Int
    /// Longest run of consecutive journaled days.
    let longestStreak: Int

    /// Derive the stats from the dream library plus the lucid lesson count.
    /// `journaledDays` should be the same set the activity grid uses (recorded
    /// dreams plus "can't remember" days) so streaks line up with what the user sees.
    init(dreams: [Dream], journaledDays: Set<Date>, lucidSections: Int) {
        dreamCount = dreams.count
        analyzedCount = dreams.filter { $0.aiMeaning != nil }.count
        distinctMoods = Set(dreams.map(\.mood)).count
        distinctTags = Set(dreams.flatMap(\.tags)).count
        self.lucidSections = lucidSections
        longestStreak = Self.longestStreak(in: journaledDays)
    }

    /// The longest chain of consecutive calendar days present in `days`.
    private static func longestStreak(in days: Set<Date>) -> Int {
        guard !days.isEmpty else { return 0 }
        let calendar = Calendar.current
        let sorted = days.map { calendar.startOfDay(for: $0) }.sorted()

        var longest = 1
        var current = 1
        for (previous, day) in zip(sorted, sorted.dropFirst()) {
            if let next = calendar.date(byAdding: .day, value: 1, to: previous),
               calendar.isDate(next, inSameDayAs: day) {
                current += 1
                longest = max(longest, current)
            } else {
                current = 1
            }
        }
        return longest
    }
}

/// A single badge. `goal` is the target value and `measure` reports how far the
/// user has progressed toward it, so the same definition drives both the
/// locked/unlocked state and the progress bar.
struct Achievement: Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let tint: Color
    let goal: Int
    /// XP awarded the moment this badge is unlocked, folded into the dreamer's total.
    let xp: Int
    let measure: (AchievementStats) -> Int

    /// Progress clamped to `0...goal`.
    func current(for stats: AchievementStats) -> Int {
        min(measure(stats), goal)
    }

    func isUnlocked(for stats: AchievementStats) -> Bool {
        measure(stats) >= goal
    }

    /// 0...1 completion fraction, for the progress bar on locked badges.
    func fraction(for stats: AchievementStats) -> Double {
        guard goal > 0 else { return 0 }
        return Double(current(for: stats)) / Double(goal)
    }
}

extension Achievement {
    /// The full badge catalog (40 badges), in display order. It's six tiered
    /// ladders that build on one another — each tier demands more than the last
    /// and pays out more XP — so progress is a continuous climb rather than a
    /// handful of one-off milestones. Tints reuse the app palette and mood colors
    /// so the grid feels of-a-piece with the rest of the app.
    static let all: [Achievement] =
        dreamLadder + streakLadder + analysisLadder + themeLadder + lucidLadder + moodLadder

    /// Total XP from every badge the dreamer has already unlocked.
    static func unlockedXP(for stats: AchievementStats) -> Int {
        all.reduce(0) { $0 + ($1.isUnlocked(for: stats) ? $1.xp : 0) }
    }

    // MARK: - Ladder builder

    private static let romanNumerals =
        ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]

    /// Builds one tiered family. Each `(goal, xp)` pair becomes a badge titled
    /// `name <tier>` (the numeral is dropped for single-tier families), all driven
    /// by the same `measure` so a single metric powers the whole ladder.
    private static func ladder(
        id: String,
        name: String,
        symbol: String,
        tint: Color,
        goalsXP: [(goal: Int, xp: Int)],
        detail: @escaping (Int) -> String,
        measure: @escaping (AchievementStats) -> Int
    ) -> [Achievement] {
        goalsXP.enumerated().map { index, tier in
            Achievement(
                id: "\(id)-\(index + 1)",
                title: goalsXP.count == 1 ? name : "\(name) \(romanNumerals[index])",
                detail: detail(tier.goal),
                symbol: symbol,
                tint: tint,
                goal: tier.goal,
                xp: tier.xp,
                measure: measure
            )
        }
    }

    // MARK: - The six ladders

    private static let dreamLadder = ladder(
        id: "dreams",
        name: "Dream Catcher",
        symbol: "book.closed.fill",
        tint: .dreamPrimary,
        goalsXP: [(1, 25), (5, 50), (10, 75), (25, 100), (50, 150),
                  (100, 250), (200, 400), (350, 600), (500, 800), (1000, 1200)],
        detail: { $0 == 1 ? "Record your first dream." : "Record \($0) dreams." },
        measure: { $0.dreamCount }
    )

    private static let streakLadder = ladder(
        id: "streak",
        name: "Unbroken",
        symbol: "flame.fill",
        tint: Dream.Mood.vivid.tint,
        goalsXP: [(3, 50), (7, 75), (14, 125), (30, 200),
                  (60, 350), (100, 500), (200, 800), (365, 1500)],
        detail: { "Journal \($0) days in a row." },
        measure: { $0.longestStreak }
    )

    private static let analysisLadder = ladder(
        id: "analysis",
        name: "Interpreter",
        symbol: "brain.head.profile",
        tint: Dream.Mood.strange.tint,
        goalsXP: [(1, 25), (5, 75), (10, 125), (25, 200),
                  (50, 350), (100, 600), (200, 1000)],
        detail: { $0 == 1 ? "Analyze a dream with AI." : "Analyze \($0) dreams with AI." },
        measure: { $0.analyzedCount }
    )

    private static let themeLadder = ladder(
        id: "themes",
        name: "Symbol Seeker",
        symbol: "tag.fill",
        tint: .dreamAccent,
        goalsXP: [(5, 50), (10, 100), (20, 175), (35, 275),
                  (50, 400), (75, 600), (100, 900)],
        detail: { "Collect \($0) distinct dream themes." },
        measure: { $0.distinctTags }
    )

    private static let lucidLadder = ladder(
        id: "lucid",
        name: "Lucid Voyager",
        symbol: "moon.stars.fill",
        tint: Dream.Mood.nightmare.tint,
        goalsXP: [(1, 75), (3, 150), (5, 250), (10, 400),
                  (15, 600), (20, 800), (30, 1200)],
        detail: { $0 == 1 ? "Complete your first lucid lesson."
                          : "Complete \($0) lucid-dreaming lessons." },
        measure: { $0.lucidSections }
    )

    private static let moodLadder = ladder(
        id: "moods",
        name: "Emotional Spectrum",
        symbol: "heart.fill",
        tint: Dream.Mood.joyful.tint,
        goalsXP: [(Dream.Mood.allCases.count, 150)],
        detail: { _ in "Log a dream in every mood." },
        measure: { $0.distinctMoods }
    )
}
