//
//  Dream.swift
//  HalfLight
//
//  Created by Ryan Lewandowski on 6/13/26.
//

import Foundation

/// A single recorded dream entry.
struct Dream: Identifiable, Hashable {
    let id: UUID
    var title: String
    var entry: String
    var date: Date
    var mood: Mood
    /// AI-generated themes/symbols extracted from the dream.
    var tags: [String]

    init(
        id: UUID = UUID(),
        title: String,
        entry: String,
        date: Date,
        mood: Mood,
        tags: [String] = []
    ) {
        self.id = id
        self.title = title
        self.entry = entry
        self.date = date
        self.mood = mood
        self.tags = tags
    }
}

extension Dream {
    /// The emotional tone of a dream, used for color + iconography.
    enum Mood: String, CaseIterable, Identifiable {
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
    /// Sample dreams used for previews and the initial home screen.
    static let samples: [Dream] = [
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
