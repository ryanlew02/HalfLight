//
//  Quest.swift
//  HalfLight
//
//  Weekly quests shown on the Progress screen. Five quests are drawn each week
//  from a themed pool (journaling, consistency, lucid recall, analysis, moods,
//  themes, depth). The draw is pseudo-random but seeded by the week's start date,
//  so the same five stay put for the whole week and reshuffle next Monday.
//
//  Quests are measured against data the app already tracks for the current week,
//  so progress needs no extra persistence — only the XP banked when a quest is
//  completed is stored (so it survives the week rolling over). That banked XP is
//  folded into the dreamer's total, alongside journaling and achievement XP.
//

import SwiftUI

/// The metrics every quest is evaluated against, built once per render from the
/// dreams logged in the current week plus that week's journaled-day count.
struct QuestStats: Equatable {
    let dreamsThisWeek: Int
    let journaledDaysThisWeek: Int
    let analyzedThisWeek: Int
    let distinctMoodsThisWeek: Int
    let distinctTagsThisWeek: Int
    let taggedDreamsThisWeek: Int
    /// Word count of the longest dream entry recorded this week.
    let longestEntryWords: Int
    let currentStreak: Int

    init(weekDreams: [Dream], journaledDaysThisWeek: Int, currentStreak: Int) {
        dreamsThisWeek = weekDreams.count
        analyzedThisWeek = weekDreams.filter { $0.aiMeaning != nil }.count
        distinctMoodsThisWeek = Set(weekDreams.map(\.mood)).count
        distinctTagsThisWeek = Set(weekDreams.flatMap(\.tags)).count
        taggedDreamsThisWeek = weekDreams.filter { !$0.tags.isEmpty }.count
        longestEntryWords = weekDreams
            .map { $0.entry.split(whereSeparator: \.isWhitespace).count }
            .max() ?? 0
        self.journaledDaysThisWeek = journaledDaysThisWeek
        self.currentStreak = currentStreak
    }
}

/// The themed families a weekly draw spreads across, so the five quests always
/// feel varied (one per category) rather than five flavors of the same task.
enum QuestCategory: String, CaseIterable, Comparable {
    case journaling, consistency, lucid, analysis, moods, themes, depth

    static func < (lhs: QuestCategory, rhs: QuestCategory) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A single weekly objective. `goal` is the target and `measure` reports progress
/// from the week's stats, so one definition drives the bar and the done state.
struct Quest: Identifiable {
    let id: String
    let category: QuestCategory
    let title: String
    let detail: String
    let symbol: String
    let tint: Color
    let goal: Int
    /// XP banked once when the quest is completed.
    let xp: Int
    let measure: (QuestStats) -> Int

    func current(for stats: QuestStats) -> Int { min(measure(stats), goal) }
    func isComplete(for stats: QuestStats) -> Bool { measure(stats) >= goal }
    func fraction(for stats: QuestStats) -> Double {
        guard goal > 0 else { return 0 }
        return Double(current(for: stats)) / Double(goal)
    }
}

extension Quest {
    /// Bonus XP granted for completing all of the week's quests — more than any
    /// single quest pays, as a reward for clearing the whole board.
    static let allCompleteBonusXP = 300

    /// The full pool a week's quests are drawn from. At least one per category so
    /// every weekly draw can cover five distinct categories.
    static let pool: [Quest] = [
        // Journaling
        Quest(id: "log3", category: .journaling, title: "Faithful Journal",
              detail: "Record 3 dreams this week", symbol: "book.fill",
              tint: .dreamPrimary, goal: 3, xp: 60, measure: { $0.dreamsThisWeek }),
        Quest(id: "log5", category: .journaling, title: "Dream Devotion",
              detail: "Record 5 dreams this week", symbol: "books.vertical.fill",
              tint: .dreamPrimary, goal: 5, xp: 110, measure: { $0.dreamsThisWeek }),
        Quest(id: "log2", category: .journaling, title: "Catch the Fading",
              detail: "Record 2 dreams before they slip away", symbol: "moon.zzz.fill",
              tint: Dream.Mood.peaceful.tint, goal: 2, xp: 50, measure: { $0.dreamsThisWeek }),

        // Consistency
        Quest(id: "days4", category: .consistency, title: "Steady Nights",
              detail: "Journal on 4 different days", symbol: "calendar",
              tint: .dreamAccent, goal: 4, xp: 80, measure: { $0.journaledDaysThisWeek }),
        Quest(id: "days7", category: .consistency, title: "Perfect Week",
              detail: "Journal every day this week", symbol: "calendar.badge.checkmark",
              tint: .dreamAccent, goal: 7, xp: 160, measure: { $0.journaledDaysThisWeek }),
        Quest(id: "streak3", category: .consistency, title: "On a Roll",
              detail: "Reach a 3-day streak", symbol: "flame.fill",
              tint: Dream.Mood.vivid.tint, goal: 3, xp: 70, measure: { $0.currentStreak }),

        // Lucid (recall & awareness — the groundwork of lucid dreaming)
        Quest(id: "lucid-recall", category: .lucid, title: "Reality Check",
              detail: "Log 4 dreams to sharpen lucid awareness", symbol: "eye.fill",
              tint: Dream.Mood.nightmare.tint, goal: 4, xp: 100, measure: { $0.dreamsThisWeek }),
        Quest(id: "lucid-ritual", category: .lucid, title: "Nightly Ritual",
              detail: "Build the lucid habit — journal 5 days", symbol: "moon.stars.fill",
              tint: Dream.Mood.nightmare.tint, goal: 5, xp: 120, measure: { $0.journaledDaysThisWeek }),

        // Analysis
        Quest(id: "analyze1", category: .analysis, title: "Seek Meaning",
              detail: "Analyze a dream with AI", symbol: "sparkles",
              tint: Dream.Mood.strange.tint, goal: 1, xp: 50, measure: { $0.analyzedThisWeek }),
        Quest(id: "analyze2", category: .analysis, title: "Inner Eye",
              detail: "Analyze 2 dreams with AI", symbol: "brain.head.profile",
              tint: Dream.Mood.strange.tint, goal: 2, xp: 90, measure: { $0.analyzedThisWeek }),

        // Moods
        Quest(id: "moods3", category: .moods, title: "Shifting Tides",
              detail: "Log dreams in 3 different moods", symbol: "theatermasks.fill",
              tint: Dream.Mood.joyful.tint, goal: 3, xp: 80, measure: { $0.distinctMoodsThisWeek }),
        Quest(id: "moods5", category: .moods, title: "Full Spectrum",
              detail: "Log dreams in 5 different moods", symbol: "paintpalette.fill",
              tint: Dream.Mood.euphoric.tint, goal: 5, xp: 130, measure: { $0.distinctMoodsThisWeek }),

        // Themes / tags
        Quest(id: "tags5", category: .themes, title: "Symbol Hunter",
              detail: "Collect 5 dream themes this week", symbol: "tag.fill",
              tint: .dreamAccent, goal: 5, xp: 80, measure: { $0.distinctTagsThisWeek }),
        Quest(id: "tagged3", category: .themes, title: "Tag the Signs",
              detail: "Add themes to 3 dreams", symbol: "number",
              tint: .dreamAccent, goal: 3, xp: 70, measure: { $0.taggedDreamsThisWeek }),

        // Depth
        Quest(id: "depth60", category: .depth, title: "Vivid Recall",
              detail: "Write a 60-word dream entry", symbol: "text.alignleft",
              tint: Dream.Mood.exciting.tint, goal: 60, xp: 90, measure: { $0.longestEntryWords }),
        Quest(id: "depth120", category: .depth, title: "Deep Dive",
              detail: "Write a 120-word dream entry", symbol: "text.book.closed.fill",
              tint: Dream.Mood.exciting.tint, goal: 120, xp: 150, measure: { $0.longestEntryWords })
    ]

    /// Start of the current week (Monday), matching the Home week tracker so the
    /// "journaled days this week" count lines up with what the dreamer sees there.
    static func weekStart(for date: Date = .now, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: today) // 1 = Sun … 7 = Sat
        let daysFromMonday = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -daysFromMonday, to: today) ?? today
    }

    /// The five quests for the week containing `date`. Seeded by the week's start
    /// so the draw is stable all week, then spread across five distinct categories
    /// for variety. Sorting before each shuffle keeps the result deterministic.
    static func weekly(for date: Date = .now, count: Int = 5) -> [Quest] {
        let start = weekStart(for: date)
        // Mix the week start with the account's quest seed: quests still rotate
        // weekly, but each account (and each fresh guest after a sign-out) draws a
        // different board rather than everyone sharing the same five.
        let weekSeed = UInt64(bitPattern: Int64(start.timeIntervalSince1970))
        var rng = QuestRandomGenerator(seed: weekSeed ^ QuestSeed.current)
        let categories = QuestCategory.allCases.sorted().shuffled(using: &rng).prefix(count)
        return categories.compactMap { category in
            pool.filter { $0.category == category }
                .sorted { $0.id < $1.id }
                .shuffled(using: &rng)
                .first
        }
    }

    /// The week's quests plus the stats they're measured against, derived from the
    /// full dream library and the journaled-day set. Shared by Home, the Progress
    /// screen, and the all-quests screen so they always agree.
    static func currentWeek(dreams: [Dream], journaledDays: Set<Date>)
        -> (quests: [Quest], stats: QuestStats) {
        let start = weekStart()
        let stats = QuestStats(
            weekDreams: dreams.filter { $0.date >= start },
            journaledDaysThisWeek: journaledDays.filter { $0 >= start }.count,
            currentStreak: Streak.from(journaledDays: journaledDays).current
        )
        return (weekly(), stats)
    }

    /// The incomplete quest nearest to completion, or `nil` when every quest is done.
    static func closestIncomplete(in quests: [Quest], stats: QuestStats) -> Quest? {
        quests
            .filter { !$0.isComplete(for: stats) }
            .max { $0.fraction(for: stats) < $1.fraction(for: stats) }
    }

    /// "Resets in 3d" / "Resets tomorrow" / "Resets today" — days until next Monday.
    static var resetText: String {
        let calendar = Calendar.current
        guard let nextReset = calendar.date(byAdding: .day, value: 7, to: weekStart()) else {
            return ""
        }
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: .now), to: nextReset
        ).day ?? 0
        switch days {
        case ...0: return "Resets today"
        case 1: return "Resets tomorrow"
        default: return "Resets in \(days)d"
        }
    }
}

/// The seed that personalizes the weekly quest draw.
///
/// When signed in, it's derived deterministically from the account's user id, so
/// the board is a pure function of (account, week): identical on every device,
/// and restored automatically on sign-in without any server round-trip. When
/// signed out (guest), it falls back to a stored random seed that's rolled fresh
/// on sign-out — so a guest sees a new board, but the account's board is untouched
/// and returns the moment they sign back in.
enum QuestSeed {
    private static let key = "questSeed"

    static var current: UInt64 {
        // Signed in: tie the board to the account id (the same marker DreamStore
        // stamps on sign-in and clears on sign-out), so it never drifts.
        if let uid = UserDefaults.standard.string(forKey: DreamStore.lastOwnerKey), !uid.isEmpty {
            return deterministicSeed(from: uid)
        }
        // Guest: a stored random seed, generated once and kept until sign-out.
        if let stored = UserDefaults.standard.object(forKey: key) as? NSNumber {
            return stored.uint64Value
        }
        let seed = UInt64.random(in: .min ... .max)
        UserDefaults.standard.set(NSNumber(value: seed), forKey: key)
        return seed
    }

    /// Roll a brand-new random guest board (used on sign-out). No-op for the
    /// account board, which is derived from the account id and so can't be lost.
    static func regenerate() {
        UserDefaults.standard.set(NSNumber(value: UInt64.random(in: .min ... .max)), forKey: key)
    }

    /// A stable 64-bit hash of `string` (FNV-1a over its UTF-8 bytes). Unlike
    /// Swift's `Hasher`, which is seeded randomly per process, this reproduces the
    /// same value across launches and devices — essential for a stable board.
    private static func deterministicSeed(from string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }
}

/// A small deterministic RNG (SplitMix64) so a seed reproduces the same sequence
/// every launch — used to keep each week's quest draw stable.
struct QuestRandomGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed != 0 ? seed : 0x9E3779B97F4A7C15
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// Tracks which completed quests have had their XP claimed, so a quest can only
/// ever pay out once per week (keyed by week + quest id). Completing a quest no
/// longer grants XP automatically — the dreamer claims it from a quest's Claim
/// button, which banks the XP and fires the reward animation.
enum QuestRewards {
    // Reuses the original "completed" key so quests whose XP was already banked
    // under the old auto-grant flow count as claimed (no double payout).
    static let claimedKey = "questCompletedKeys"

    /// Synthetic id for the once-a-week "all quests complete" bonus.
    static let allCompleteBonusID = "all-complete-bonus"

    private static func key(_ id: String, weekStart: Date) -> String {
        "\(Int(weekStart.timeIntervalSince1970))-\(id)"
    }

    private static func claimedKeys() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: claimedKey) ?? [])
    }

    /// Whether the reward keyed by `id` has already been claimed this week.
    private static func isClaimed(id: String, weekStart: Date) -> Bool {
        claimedKeys().contains(key(id, weekStart: weekStart))
    }

    /// Record a claim for `id` and return the updated banked-XP total. Idempotent:
    /// an already-claimed reward leaves the total unchanged.
    private static func claim(id: String, xp: Int, weekStart: Date, currentTotal: Int) -> Int {
        var claimed = claimedKeys()
        guard claimed.insert(key(id, weekStart: weekStart)).inserted else {
            return currentTotal
        }
        UserDefaults.standard.set(Array(claimed), forKey: claimedKey)
        return currentTotal + xp
    }

    // MARK: Individual quests

    /// Whether this quest's reward has already been claimed this week.
    static func isClaimed(_ quest: Quest, weekStart: Date) -> Bool {
        isClaimed(id: quest.id, weekStart: weekStart)
    }

    /// A completed quest whose XP is waiting to be claimed.
    static func isClaimable(_ quest: Quest, stats: QuestStats, weekStart: Date) -> Bool {
        quest.isComplete(for: stats) && !isClaimed(quest, weekStart: weekStart)
    }

    static func claim(_ quest: Quest, weekStart: Date, currentTotal: Int) -> Int {
        claim(id: quest.id, xp: quest.xp, weekStart: weekStart, currentTotal: currentTotal)
    }

    // MARK: All-quests-complete bonus

    static func isBonusClaimed(weekStart: Date) -> Bool {
        isClaimed(id: allCompleteBonusID, weekStart: weekStart)
    }

    /// The bonus is ready once every quest for the week is complete and the bonus
    /// itself hasn't been claimed yet.
    static func isBonusClaimable(quests: [Quest], stats: QuestStats, weekStart: Date) -> Bool {
        !quests.isEmpty
            && quests.allSatisfy { $0.isComplete(for: stats) }
            && !isBonusClaimed(weekStart: weekStart)
    }

    static func claimBonus(weekStart: Date, currentTotal: Int) -> Int {
        claim(id: allCompleteBonusID, xp: Quest.allCompleteBonusXP, weekStart: weekStart, currentTotal: currentTotal)
    }

    // MARK: Reset

    /// The `@AppStorage` key holding the banked quest XP folded into the dreamer's
    /// total. Reset together with the claimed-quest records so quests start fresh.
    static let bankedXPKey = "questBankedXP"

    /// Forget every claimed-quest record and the banked quest XP, and roll a fresh
    /// quest board (used on sign-out so the next account on this device starts the
    /// week's quests from scratch with a brand-new set).
    static func reset() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: claimedKey)
        defaults.removeObject(forKey: bankedXPKey)
        QuestSeed.regenerate()
    }
}
