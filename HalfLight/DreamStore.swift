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
    /// Whether the dream may be shared publicly. Defaults to private.
    var isPublic: Bool = false
    /// Whether the dreamer was lucid. Defaults to non-lucid.
    var isLucid: Bool = false
    /// Optional AI analysis generated in the form before saving. Carried through so
    /// a dream can be created already-interpreted, and so editing preserves an
    /// existing interpretation (or replaces it when re-analyzed).
    var aiCategory: String? = nil
    var aiMeaning: String? = nil
    var aiThemes: [String] = []
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

    /// Days marked "can't remember", and days whose journaling XP must outlive a
    /// deleted dream. Held here — rather than read straight from `DayLog` in the
    /// views — so SwiftUI re-renders the instant either changes; `DayLog` remains
    /// the UserDefaults-backed persistence layer behind them.
    private(set) var skippedDays: Set<Date> = DayLog.skipped.days()
    private(set) var creditedDays: Set<Date> = DayLog.journalCredit.days()

    init(context: ModelContext, sync: DreamSyncing? = nil) {
        self.context = context
        self.sync = sync
    }

    // MARK: - Mutations

    /// Mark today as journaled even when no dream was recorded ("can't remember").
    /// Idempotent per day; bumps the observable set so XP updates immediately.
    func recordSkippedDay(_ date: Date = .now) {
        DayLog.skipped.record(date)
        skippedDays = DayLog.skipped.days()
    }

    /// Create and persist a new dream from the form draft, returning it so the
    /// caller can navigate straight to its detail view.
    @discardableResult
    func add(_ draft: DreamDraft) -> Dream {
        let dream = Dream(
            title: draft.title,
            entry: draft.entry,
            date: .now,
            mood: draft.mood,
            tags: draft.tags,
            isPublic: draft.isPublic,
            isLucid: draft.isLucid,
            aiCategory: draft.aiCategory,
            aiMeaning: draft.aiMeaning,
            aiThemes: draft.aiThemes
        )
        context.insert(dream)
        syncFeedPost(for: dream)
        save()
        pushRemote(dream)
        return dream
    }

    /// Apply edited values to an existing dream.
    func update(_ dream: Dream, with draft: DreamDraft) {
        dream.title = draft.title
        dream.entry = draft.entry
        dream.mood = draft.mood
        dream.tags = draft.tags
        dream.isPublic = draft.isPublic
        dream.isLucid = draft.isLucid
        dream.aiCategory = draft.aiCategory
        dream.aiMeaning = draft.aiMeaning
        dream.aiThemes = draft.aiThemes
        dream.updatedAt = .now
        dream.needsUpload = true
        syncFeedPost(for: dream)
        save()
        pushRemote(dream)
    }

    /// Store the AI analysis (category, meaning, and central themes) for a dream.
    func setAnalysis(_ dream: Dream, category: String, meaning: String, themes: [String]) {
        dream.aiCategory = category
        dream.aiMeaning = meaning
        dream.aiThemes = themes
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
        // Preserve the day's journaling XP: once a day has been credited, deleting
        // the dream that earned it must not claw the XP back.
        DayLog.journalCredit.record(dream.date)
        creditedDays = DayLog.journalCredit.days()
        // Pull its feed post too, so a shared dream can't linger on the feed.
        let postDescriptor = FetchDescriptor<FeedPost>(predicate: #Predicate<FeedPost> { $0.dreamID == id })
        for post in (try? context.fetch(postDescriptor)) ?? [] {
            context.delete(post)
        }
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

    // MARK: - Feed

    /// Keep a dream's feed presence in step with its visibility: a public dream
    /// has exactly one `FeedPost` (created when it's first made public, its
    /// snapshot refreshed on later edits); a private dream has none. The author's
    /// handle / name / photo are snapshotted from the signed-in profile so the
    /// card renders without a server round-trip (mirroring the future feed sync).
    private func syncFeedPost(for dream: Dream) {
        let dreamID = dream.id
        let descriptor = FetchDescriptor<FeedPost>(predicate: #Predicate<FeedPost> { $0.dreamID == dreamID })
        let existing = (try? context.fetch(descriptor)) ?? []

        guard dream.isPublic else {
            existing.forEach(context.delete)
            return
        }

        if let post = existing.first {
            // Already shared — keep the snapshot in step with the dream's edits.
            post.title = dream.title
            post.dreamDescription = dream.entry
        } else {
            let author = currentAuthor()
            context.insert(FeedPost(
                dreamID: dream.id,
                authorUsername: author.username,
                authorName: author.name,
                authorPhoto: author.photo,
                title: dream.title,
                dreamDescription: dream.entry
            ))
        }
    }

    /// Reconcile every dream's feed presence with its visibility in one pass.
    /// Called at launch so dreams already marked public — including any from
    /// before visibility drove the feed — get their post created (and any stale
    /// posts for now-private dreams cleaned up).
    func backfillFeedPosts() {
        let dreams = (try? context.fetch(FetchDescriptor<Dream>())) ?? []
        dreams.forEach(syncFeedPost)
        save()
    }

    /// Re-snapshot every feed post's author (photo / name / handle) from the
    /// current profile, so editing your profile shows up on dreams you've already
    /// shared. All posts belong to the signed-in dreamer until a multi-user
    /// backend exists, so this is where a periodic remote profile sync will live.
    /// Cheap and idempotent — only writes when something actually changed.
    func refreshFeedAuthors() {
        let posts = (try? context.fetch(FetchDescriptor<FeedPost>())) ?? []
        guard !posts.isEmpty else { return }
        let author = currentAuthor()
        var changed = false
        for post in posts {
            if post.authorName != author.name { post.authorName = author.name; changed = true }
            if post.authorUsername != author.username { post.authorUsername = author.username; changed = true }
            if post.authorPhoto != author.photo { post.authorPhoto = author.photo; changed = true }
        }
        if changed { save() }
    }

    /// The signed-in dreamer's author snapshot, read from the profile defaults that
    /// the Profile screen writes (`userName`, `userUsername`, `profilePhoto`).
    private func currentAuthor() -> (name: String, username: String, photo: Data?) {
        let defaults = UserDefaults.standard
        let name = defaults.string(forKey: "userName") ?? "Dreamer"
        let username = defaults.string(forKey: "userUsername") ?? name.lowercased()
        return (name, username, defaults.data(forKey: "profilePhoto"))
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
            aiThemes: aiThemes,
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
            aiThemes: aiThemes ?? [],
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
        dream.aiThemes = aiThemes ?? []
        dream.updatedAt = updatedAt
    }
}

#if DEBUG
@MainActor
enum PreviewData {
    /// An in-memory container seeded with samples, for SwiftUI previews.
    static let container: ModelContainer = {
        let container = try! ModelContainer(
            for: Dream.self, DeletedDream.self, FeedPost.self, Follow.self,
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

// MARK: - Progression

extension DreamStore {
    /// The dreamer's total XP — the single source of truth for level and rank,
    /// shared by the Progress screen, the Profile rank badge, and the level-up
    /// detector so they can never disagree. Folds together journaling-credit days
    /// (recorded, "can't remember", or credited by a since-deleted dream),
    /// completed lucid sections, unlocked-achievement XP, and banked quest XP.
    func totalXP(dreams: [Dream], lucidSections: Int, questBankedXP: Int) -> Int {
        let calendar = Calendar.current
        let dreamDays = Set(dreams.map { calendar.startOfDay(for: $0.date) })
        // Every day that has earned journaling XP, capped at one credit per day.
        let xpEarningDays = dreamDays.union(skippedDays).union(creditedDays)
        // Achievement progress is measured against recorded/skipped days only.
        let journaledDays = dreamDays.union(skippedDays)
        let stats = AchievementStats(
            dreams: dreams,
            journaledDays: journaledDays,
            lucidSections: lucidSections
        )
        return DreamProgression.totalXP(
            journaledDays: xpEarningDays.count,
            lucidSections: lucidSections,
            achievementXP: Achievement.unlockedXP(for: stats)
        ) + questBankedXP
    }
}
