//
//  DreamStore.swift
//  HalfLight
//
//  Write/sync service over the SwiftData store. Reads happen via @Query in the
//  views (always live); every mutation goes through here, which is where the
//  Supabase sync layer will hook in later.
//

import Foundation
import SwiftData

/// The values captured by the add/edit form, independent of persistence.
struct DreamDraft {
    var title: String
    var entry: String
    var mood: Dream.Mood
    var tags: [String]
}

@MainActor
@Observable
final class DreamStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Mutations

    /// Create and persist a new dream from the form draft.
    func add(_ draft: DreamDraft) {
        let dream = Dream(
            title: draft.title,
            entry: draft.entry,
            date: .now,
            mood: draft.mood,
            tags: draft.tags
        )
        context.insert(dream)
        save()
    }

    /// Apply edited values to an existing dream.
    func update(_ dream: Dream, with draft: DreamDraft) {
        dream.title = draft.title
        dream.entry = draft.entry
        dream.mood = draft.mood
        dream.tags = draft.tags
        dream.updatedAt = .now
        dream.needsUpload = true
        save()
    }

    /// Delete a dream from the store.
    func delete(_ dream: Dream) {
        context.delete(dream)
        save()
    }

    // MARK: - Seeding

    private static let didSeedKey = "didSeedSampleDreams"

    /// Seed sample dreams on first launch only. Dev convenience — remove before shipping
    /// real accounts so users don't start with fabricated entries.
    func seedSampleDataIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.didSeedKey) else { return }
        let existing = (try? context.fetchCount(FetchDescriptor<Dream>())) ?? 0
        if existing == 0 {
            for dream in Dream.makeSamples() {
                context.insert(dream)
            }
            save()
        }
        UserDefaults.standard.set(true, forKey: Self.didSeedKey)
    }

    // MARK: - Internals

    private func save() {
        do {
            try context.save()
        } catch {
            assertionFailure("Failed to save dream context: \(error)")
        }
    }
}

#if DEBUG
@MainActor
enum PreviewData {
    /// An in-memory container seeded with samples, for SwiftUI previews.
    static let container: ModelContainer = {
        let container = try! ModelContainer(
            for: Dream.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        for dream in Dream.makeSamples() {
            container.mainContext.insert(dream)
        }
        try? container.mainContext.save()
        return container
    }()

    static var store: DreamStore { DreamStore(context: container.mainContext) }
}
#endif
