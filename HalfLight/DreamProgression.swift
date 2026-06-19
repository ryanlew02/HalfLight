//
//  DreamProgression.swift
//  HalfLight
//
//  The XP / level model, shared between the Profile progress card and the
//  Levels detail screen so they always agree.
//
//  Placeholder economy for now: journal entries and completed lucid sections
//  award XP, and every `xpPerLevel` XP is a new Dreamer level. Levels map onto
//  named ranks (Rookie Dreamer → … → Oneironaut).
//

import Foundation

enum DreamProgression {
    static let xpPerLevel = 100
    static let xpPerJournalEntry = 10
    static let xpPerLucidSection = 50

    static func totalXP(journalEntries: Int, lucidSections: Int, achievementXP: Int = 0) -> Int {
        journalEntries * xpPerJournalEntry
            + lucidSections * xpPerLucidSection
            + achievementXP
    }

    static func level(forXP xp: Int) -> Int { xp / xpPerLevel + 1 }
    static func xpIntoLevel(forXP xp: Int) -> Int { xp % xpPerLevel }
    static func progress(forXP xp: Int) -> Double {
        Double(xpIntoLevel(forXP: xp)) / Double(xpPerLevel)
    }

    struct Rank: Identifiable, Equatable {
        let name: String
        let minLevel: Int
        var id: Int { minLevel }
    }

    /// Named ranks in ascending order, each unlocking at `minLevel`.
    static let ranks: [Rank] = [
        Rank(name: "Drowsy Wanderer", minLevel: 1),
        Rank(name: "Dream Seeker", minLevel: 5),
        Rank(name: "Night Voyager", minLevel: 10),
        Rank(name: "Reverie Adept", minLevel: 18),
        Rank(name: "Lucid Initiate", minLevel: 28),
        Rank(name: "Dream Walker", minLevel: 40),
        Rank(name: "Astral Pathfinder", minLevel: 54),
        Rank(name: "Vision Weaver", minLevel: 70),
        Rank(name: "Dream Architect", minLevel: 88),
        Rank(name: "Lucid Sovereign", minLevel: 108),
        Rank(name: "Oneironaut", minLevel: 130),
        Rank(name: "The Awakened", minLevel: 155)
    ]

    /// The highest rank unlocked at the given level.
    static func rank(forLevel level: Int) -> Rank {
        ranks.last { level >= $0.minLevel } ?? ranks[0]
    }
}
