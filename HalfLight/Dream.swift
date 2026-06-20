//
//  Dream.swift
//  HalfLight
//
//  Created by Ryan Lewandowski on 6/13/26.
//

import Foundation
import SwiftData

/// A single recorded dream entry, persisted locally via SwiftData.
///
/// Local SwiftData is the source of truth. The `remoteID` / `userID` /
/// `updatedAt` / `needsUpload` fields drive the Supabase sync layer (see
/// `DreamStore` / `DreamSync`) that backs dreams up while the user is signed in.
@Model
final class Dream {
    /// Stable local identifier. Also used to match against the remote row once synced.
    @Attribute(.unique) var id: UUID
    var title: String
    var entry: String
    var date: Date
    var mood: Mood
    /// AI-generated themes/symbols extracted from the dream.
    var tags: [String]

    // MARK: AI analysis (populated by the "Analyze with AI" action)

    /// AI-assigned category for the dream (e.g. "Nightmare", "Symbolic"); `nil` until analyzed.
    var aiCategory: String?
    /// AI-generated interpretation of what the dream may mean; `nil` until analyzed.
    var aiMeaning: String?
    /// The 2–3 central themes the AI surfaced for this dream; empty until analyzed.
    /// These drive the "Top themes" on the Profile screen (distinct from `tags`).
    var aiThemes: [String] = []

    // MARK: Supabase sync state

    /// The Supabase row id once this dream has been uploaded; `nil` while local-only.
    var remoteID: UUID?
    /// The owning Supabase auth user; `nil` while anonymous (pre-account).
    var userID: String?
    /// Last local modification — drives last-write-wins conflict resolution later.
    var updatedAt: Date
    /// `true` when there are local changes not yet pushed to the server.
    var needsUpload: Bool

    init(
        id: UUID = UUID(),
        title: String,
        entry: String,
        date: Date,
        mood: Mood,
        tags: [String] = [],
        aiCategory: String? = nil,
        aiMeaning: String? = nil,
        aiThemes: [String] = [],
        remoteID: UUID? = nil,
        userID: String? = nil,
        updatedAt: Date = .now,
        needsUpload: Bool = true
    ) {
        self.id = id
        self.title = title
        self.entry = entry
        self.date = date
        self.mood = mood
        self.tags = tags
        self.aiCategory = aiCategory
        self.aiMeaning = aiMeaning
        self.aiThemes = aiThemes
        self.remoteID = remoteID
        self.userID = userID
        self.updatedAt = updatedAt
        self.needsUpload = needsUpload
    }
}

extension Dream {
    /// The emotional tone of a dream, used for color + iconography.
    enum Mood: String, CaseIterable, Identifiable, Codable {
        case peaceful = "Peaceful"
        case joyful = "Joyful"
        case strange = "Strange"
        case anxious = "Anxious"
        case vivid = "Vivid"
        case nightmare = "Nightmare"
        case romantic = "Romantic"
        case sad = "Sad"
        case exciting = "Exciting"
        case mysterious = "Mysterious"
        case lonely = "Lonely"
        case hopeful = "Hopeful"
        case nostalgic = "Nostalgic"
        case euphoric = "Euphoric"

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .peaceful: "moon.stars.fill"
            case .joyful: "sun.max.fill"
            case .strange: "sparkles"
            case .anxious: "wind"
            case .vivid: "wand.and.stars"
            case .nightmare: "cloud.bolt.rain.fill"
            case .romantic: "heart.fill"
            case .sad: "cloud.rain.fill"
            case .exciting: "bolt.fill"
            case .mysterious: "moon.fill"
            case .lonely: "cloud.fog.fill"
            case .hopeful: "sunrise.fill"
            case .nostalgic: "hourglass"
            case .euphoric: "star.fill"
            }
        }
    }
}

extension Dream {
    /// Fresh sample dreams for first-run seeding and previews.
    ///
    /// Returns new instances each call — `@Model` objects are reference types and a
    /// given instance can only be inserted into one context.
    static func makeSamples() -> [Dream] {
        [
            Dream(
                title: "The Floating Library",
                entry: "I wandered through a library where the books drifted off the shelves and rearranged themselves into staircases. Each step I climbed revealed a new memory I'd forgotten.",
                date: .now.addingTimeInterval(-60 * 60 * 8),
                mood: .vivid,
                tags: ["memory", "flight", "knowledge"],
                aiThemes: ["Memory", "Discovery", "Flight"]
            ),
            Dream(
                title: "Tide of Strangers",
                entry: "A crowd of faceless people moved like a tide along a shoreline. They were calm, and somehow I knew all of their names.",
                date: .now.addingTimeInterval(-60 * 60 * 30),
                mood: .strange,
                tags: ["crowds", "ocean", "identity"],
                aiThemes: ["Identity", "Belonging"]
            ),
            Dream(
                title: "Garden After Rain",
                entry: "I sat in my grandmother's garden just after a storm. Everything smelled green and new, and the sky was that impossible color it gets at dusk.",
                date: .now.addingTimeInterval(-60 * 60 * 52),
                mood: .peaceful,
                tags: ["nostalgia", "nature", "family"],
                aiThemes: ["Nostalgia", "Family", "Renewal"]
            )
        ]
    }

    /// A single standalone sample for SwiftUI previews.
    static var preview: Dream { makeSamples()[0] }
}
