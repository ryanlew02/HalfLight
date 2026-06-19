//
//  DreamProgression.swift
//  HalfLight
//
//  The XP / level model, shared between the Profile progress card and the
//  Levels detail screen so they always agree.
//
//  Placeholder economy for now: journal entries and completed lucid sections
//  award XP. Levels follow a rising curve — each level costs more XP than the
//  one before it — and map onto named ranks (Drowsy Wanderer → … → The Awakened).
//

import Foundation

enum DreamProgression {
    /// Earned once per day the dreamer journals — whether they record a dream or
    /// mark the night as forgotten. A day can never be worth more than this, and
    /// the credit survives deleting the dream that earned it.
    static let xpPerJournaledDay = 10
    static let xpPerLucidSection = 50

    /// XP curve. Advancing from level `L` to `L + 1` costs
    /// `baseLevelXP + levelXPStep * (L - 1)`, so the first level is cheap and
    /// every subsequent level demands steadily more.
    ///
    /// Tuned so a dedicated dreamer — journaling daily, finishing the lucid path,
    /// and unlocking most achievements (~14k XP/year) — reaches the top rank
    /// ("The Awakened", level 50, ~13.7k cumulative XP) in about a year. The final
    /// level alone costs 520 XP (≈52 journal entries) versus 40 for the first.
    static let baseLevelXP = 40
    static let levelXPStep = 10

    static func totalXP(journaledDays: Int, lucidSections: Int, achievementXP: Int = 0) -> Int {
        journaledDays * xpPerJournaledDay
            + lucidSections * xpPerLucidSection
            + achievementXP
    }

    /// XP needed to advance from `level` to the next one.
    static func xpToAdvance(fromLevel level: Int) -> Int {
        baseLevelXP + levelXPStep * (max(level, 1) - 1)
    }

    /// Cumulative XP required to first reach `level` (level 1 needs 0).
    /// Closed form of the arithmetic series of per-level costs.
    static func xpToReach(level: Int) -> Int {
        let advances = max(level, 1) - 1
        return advances * baseLevelXP + levelXPStep * (advances * (advances - 1)) / 2
    }

    static func level(forXP xp: Int) -> Int {
        var level = 1
        while xp >= xpToReach(level: level + 1) { level += 1 }
        return level
    }

    /// XP earned since reaching the current level.
    static func xpIntoLevel(forXP xp: Int) -> Int {
        xp - xpToReach(level: level(forXP: xp))
    }

    /// XP required to clear the dreamer's current level.
    static func xpForCurrentLevel(forXP xp: Int) -> Int {
        xpToAdvance(fromLevel: level(forXP: xp))
    }

    static func progress(forXP xp: Int) -> Double {
        Double(xpIntoLevel(forXP: xp)) / Double(xpForCurrentLevel(forXP: xp))
    }

    struct Rank: Identifiable, Equatable {
        let name: String
        let minLevel: Int
        var id: Int { minLevel }
    }

    /// Named ranks in ascending order, each unlocking at `minLevel`.
    static let ranks: [Rank] = [
        Rank(name: "Drowsy Wanderer", minLevel: 1),
        Rank(name: "Dream Seeker", minLevel: 3),
        Rank(name: "Night Voyager", minLevel: 6),
        Rank(name: "Reverie Adept", minLevel: 10),
        Rank(name: "Lucid Initiate", minLevel: 15),
        Rank(name: "Dream Walker", minLevel: 20),
        Rank(name: "Astral Pathfinder", minLevel: 26),
        Rank(name: "Vision Weaver", minLevel: 32),
        Rank(name: "Dream Architect", minLevel: 38),
        Rank(name: "Lucid Sovereign", minLevel: 43),
        Rank(name: "Oneironaut", minLevel: 47),
        Rank(name: "The Awakened", minLevel: 50)
    ]

    /// The highest rank unlocked at the given level.
    static func rank(forLevel level: Int) -> Rank {
        ranks.last { level >= $0.minLevel } ?? ranks[0]
    }
}
