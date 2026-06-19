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

/// A record that a dream was deleted, kept so a later sync can never resurrect it.
/// `needsRemoteDelete` stays true until we've confirmed the row is gone from the
/// backend; until then every reconcile retries the deletion. Tombstones are
/// pruned once the remote row is confirmed absent.
@Model
final class DeletedDream {
    @Attribute(.unique) var id: UUID
    var needsRemoteDelete: Bool
    var deletedAt: Date

    init(id: UUID, needsRemoteDelete: Bool, deletedAt: Date = .now) {
        self.id = id
        self.needsRemoteDelete = needsRemoteDelete
        self.deletedAt = deletedAt
    }
}

@MainActor
@Observable
final class DreamStore {
    private let context: ModelContext
    /// Remote backup, or `nil` to stay local-only (previews, package absent).
    private let sync: DreamSyncing?

    init(context: ModelContext, sync: DreamSyncing? = nil) {
        self.context = context
        self.sync = sync
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
        pushRemote(dream)
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
        pushRemote(dream)
    }

    /// Store the AI analysis (category + meaning) returned for a dream.
    func setAnalysis(_ dream: Dream, category: String, meaning: String) {
        dream.aiCategory = category
        dream.aiMeaning = meaning
        dream.updatedAt = .now
        dream.needsUpload = true
        save()
        pushRemote(dream)
    }

    /// Delete a dream from the store, and remotely if it had been synced. A
    /// tombstone is recorded so a concurrent or later `reconcile` can never bring
    /// the dream back, and so the remote deletion is retried until it sticks.
    func delete(_ dream: Dream) {
        let id = dream.id
        let wasSynced = dream.remoteID != nil
        context.delete(dream)
        // Only tombstone when a backend is in play; local-only stores can't be
        // resurrected by a sync, so there's nothing to guard against.
        if sync != nil {
            context.insert(DeletedDream(id: id, needsRemoteDelete: wasSynced))
        }
        save()
        guard let sync, wasSynced else { return }
        Task {
            if (try? await sync.delete(id: id)) != nil {
                clearTombstone(id, ifConfirmedRemoteDelete: true)
            }
        }
    }

    /// Mark a tombstone's remote deletion as done (the row is gone from the
    /// backend); the tombstone itself lingers until a reconcile confirms absence.
    private func clearTombstone(_ id: UUID, ifConfirmedRemoteDelete: Bool) {
        guard ifConfirmedRemoteDelete else { return }
        let descriptor = FetchDescriptor<DeletedDream>(predicate: #Predicate<DeletedDream> { $0.id == id })
        guard let tomb = try? context.fetch(descriptor).first else { return }
        tomb.needsRemoteDelete = false
        save()
    }

    // MARK: - Remote sync

    /// Pull the signed-in user's remote dreams and merge them with local ones.
    /// Safe to call on every sign-in / launch-while-signed-in.
    func reconcileWithRemote() {
        guard let sync else { return }
        Task {
            guard let uid = await sync.currentUserID() else { return }
            guard let remote = try? await sync.fetchAll(for: uid) else { return }
            await merge(remote: remote, userID: uid, sync: sync)
        }
    }

    /// Best-effort upload of one dream; stamps it as synced on success.
    private func pushRemote(_ dream: Dream) {
        guard let sync else { return }
        Task {
            guard let uid = await sync.currentUserID() else { return }
            let record = dream.record(userID: uid)
            guard (try? await sync.upsert(record)) != nil else { return }
            dream.userID = uid.uuidString
            dream.remoteID = dream.id
            dream.needsUpload = false
            save()
        }
    }

    private func merge(remote: [DreamRecord], userID: UUID, sync: DreamSyncing) async {
        let locals = (try? context.fetch(FetchDescriptor<Dream>())) ?? []
        var localByID = Dictionary(locals.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let remoteIDs = Set(remote.map(\.id))

        let tombstones = (try? context.fetch(FetchDescriptor<DeletedDream>())) ?? []
        let tombstoneByID = Dictionary(tombstones.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        // Remote → local (insert new, last-write-wins on conflicts).
        for record in remote {
            // A deleted dream must never be brought back: skip the insert and make
            // sure it's queued for remote deletion (it's clearly still up there).
            if let tomb = tombstoneByID[record.id] {
                tomb.needsRemoteDelete = true
                continue
            }
            if let local = localByID[record.id] {
                if record.updatedAt > local.updatedAt {
                    record.apply(to: local)
                } else if local.updatedAt > record.updatedAt {
                    try? await sync.upsert(local.record(userID: userID))
                }
                local.userID = userID.uuidString
                local.remoteID = local.id
                local.needsUpload = false
            } else {
                let dream = record.makeDream()
                context.insert(dream)
                localByID[dream.id] = dream
            }
        }

        // Retry any remote deletions that haven't been confirmed yet (covers the
        // race where a reconcile fetched a dream before its delete landed).
        for tomb in tombstones where tomb.needsRemoteDelete {
            if (try? await sync.delete(id: tomb.id)) != nil {
                tomb.needsRemoteDelete = false
            }
        }

        // Local dreams missing remotely: either deleted elsewhere, or never
        // uploaded (anonymous / this-user) and should be pushed up.
        for local in locals where !remoteIDs.contains(local.id) {
            if local.remoteID != nil {
                context.delete(local) // it was synced before, now gone → remote deletion
            } else if local.userID == nil || local.userID == userID.uuidString {
                local.userID = userID.uuidString
                local.remoteID = local.id
                local.needsUpload = false
                try? await sync.upsert(local.record(userID: userID))
            }
            // A dream stamped with a different user is left untouched.
        }

        // Prune tombstones that are fully resolved: the remote delete is done and
        // the row is no longer coming back in the fetch. (Rows deleted in this
        // pass still appear in `remoteIDs`, so they're pruned on a later reconcile.)
        for tomb in tombstones where !tomb.needsRemoteDelete && !remoteIDs.contains(tomb.id) {
            context.delete(tomb)
        }

        save()
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

// MARK: - Dream <-> DreamRecord

extension Dream {
    /// A wire snapshot of this dream for the given owner.
    func record(userID: UUID) -> DreamRecord {
        DreamRecord(
            id: id,
            userID: userID,
            title: title,
            entry: entry,
            date: date,
            mood: mood.rawValue,
            tags: tags,
            aiCategory: aiCategory,
            aiMeaning: aiMeaning,
            updatedAt: updatedAt
        )
    }
}

extension DreamRecord {
    /// Build a fresh local dream from a remote record (already marked synced).
    func makeDream() -> Dream {
        Dream(
            id: id,
            title: title,
            entry: entry,
            date: date,
            mood: Dream.Mood(rawValue: mood) ?? .vivid,
            tags: tags,
            aiCategory: aiCategory,
            aiMeaning: aiMeaning,
            remoteID: id,
            userID: userID.uuidString,
            updatedAt: updatedAt,
            needsUpload: false
        )
    }

    /// Overwrite a local dream with this record's values (remote won).
    func apply(to dream: Dream) {
        dream.title = title
        dream.entry = entry
        dream.date = date
        dream.mood = Dream.Mood(rawValue: mood) ?? .vivid
        dream.tags = tags
        dream.aiCategory = aiCategory
        dream.aiMeaning = aiMeaning
        dream.updatedAt = updatedAt
    }
}

#if DEBUG
@MainActor
enum PreviewData {
    /// An in-memory container seeded with samples, for SwiftUI previews.
    static let container: ModelContainer = {
        let container = try! ModelContainer(
            for: Dream.self, DeletedDream.self,
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
