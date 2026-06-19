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
/// The `remoteID` / `userID` / `updatedAt` / `needsUpload` fields are local-only
/// scaffolding for the future Supabase sync layer; they have no effect yet.
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

    // MARK: Sync scaffolding (unused until Supabase is wired up)

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

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .peaceful: "moon.stars.fill"
            case .joyful: "sun.max.fill"
            case .strange: "sparkles"
            case .anxious: "wind"
            case .vivid: "wand.and.stars"
            case .nightmare: "cloud.bolt.rain.fill"
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
                tags: ["memory", "flight", "knowledge"]
            ),
            Dream(
                title: "Tide of Strangers",
                entry: "A crowd of faceless people moved like a tide along a shoreline. They were calm, and somehow I knew all of their names.",
                date: .now.addingTimeInterval(-60 * 60 * 30),
                mood: .strange,
                tags: ["crowds", "ocean", "identity"]
            ),
            Dream(
                title: "Garden After Rain",
                entry: "I sat in my grandmother's garden just after a storm. Everything smelled green and new, and the sky was that impossible color it gets at dusk.",
                date: .now.addingTimeInterval(-60 * 60 * 52),
                mood: .peaceful,
                tags: ["nostalgia", "nature", "family"]
            )
        ]
    }

    /// A single standalone sample for SwiftUI previews.
    static var preview: Dream { makeSamples()[0] }
}
