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
    /// Shared social feed backend, or `nil` to keep the feed local-only.
    private let feedSync: FeedSyncing?

    /// Days marked "can't remember", and days whose journaling XP must outlive a
    /// deleted dream. Held here — rather than read straight from `DayLog` in the
    /// views — so SwiftUI re-renders the instant either changes; `DayLog` remains
    /// the UserDefaults-backed persistence layer behind them.
    private(set) var skippedDays: Set<Date> = DayLog.skipped.days()
    private(set) var creditedDays: Set<Date> = DayLog.journalCredit.days()

    /// Set when a feed write (publishing, commenting, reporting) is rejected for
    /// hitting its per-day cap. The views observe this and show an alert, then
    /// clear it. `nil` when there's nothing to surface.
    var rateLimitNotice: String?

    init(context: ModelContext, sync: DreamSyncing? = nil, feedSync: FeedSyncing? = nil) {
        self.context = context
        self.sync = sync
        self.feedSync = feedSync
    }

    /// Re-read the cached day logs from `DayLog` after the progress sync has
    /// rewritten them, so the streak and journaled-day counts reflect the account's
    /// merged state without waiting for a relaunch.
    func refreshDayLogs() {
        skippedDays = DayLog.skipped.days()
        creditedDays = DayLog.journalCredit.days()
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
        // Push the fresh analysis onto the dream's feed post too (no-op if the
        // dream isn't shared), so it appears on the card for other dreamers.
        syncFeedPost(for: dream)
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

    // MARK: - Account lifecycle

    /// The account whose dreams currently populate the local store, remembered so a
    /// later sign-in by a *different* account can defensively clear data left behind
    /// by an interrupted sign-out. `nil` (absent) means a guest/anonymous session.
    /// Also read by `QuestSeed` to tie the weekly quest board to the account.
    static let lastOwnerKey = "lastSignedInUserID"

    /// Drop every locally cached dream, feed post, follow, comment and tombstone.
    ///
    /// Called on sign-out (and defensively when a different account signs in). The
    /// account's dreams live on the server and rehydrate via `reconcileWithRemote`
    /// on the next sign-in, so clearing the local copies keeps one person's dreams
    /// from lingering for the next person on the device. A pure guest (never signed
    /// in) never reaches this, so their local-only dreams are safe.
    func wipeLocalData() {
        deleteAll(Dream.self)
        deleteAll(FeedPost.self)
        deleteAll(Follow.self)
        deleteAll(Comment.self)
        deleteAll(AppNotification.self)
        deleteAll(DeletedDream.self)
        save()
        // The "can't remember" and journaling-XP-credit day logs live outside
        // SwiftData (UserDefaults), so they don't get cleared by the deletes above.
        // Wipe them too — otherwise the streak, journaled-day count and XP would
        // survive a sign-out and linger for the next person on this device.
        DayLog.skipped.clear()
        DayLog.journalCredit.clear()
        skippedDays = []
        creditedDays = []
        // Per-device one-time repairs should re-evaluate against the next account,
        // and the owner marker is cleared until the next sign-in re-stamps it.
        UserDefaults.standard.removeObject(forKey: "didRepublishVisibility_v1")
        UserDefaults.standard.removeObject(forKey: Self.lastOwnerKey)
    }

    private func deleteAll<T: PersistentModel>(_ type: T.Type) {
        let items = (try? context.fetch(FetchDescriptor<T>())) ?? []
        items.forEach(context.delete)
    }

    // MARK: - Remote sync

    /// One-time repair for dreams whose public/lucid flags never made it to the
    /// server (older versions didn't sync them, so a dream made public on one
    /// device looked private on another). Re-push every locally public/lucid dream
    /// with a fresh timestamp so it wins the last-write-wins merge and the flags
    /// land everywhere. Private dreams are deliberately left alone, so a device
    /// that wrongly shows a dream private never clobbers the one that has it right.
    /// Runs once per device.
    func republishVisibilityIfNeeded() {
        guard sync != nil else { return }
        let key = "didRepublishVisibility_v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)

        let flagged = ((try? context.fetch(FetchDescriptor<Dream>())) ?? [])
            .filter { $0.isPublic || $0.isLucid }
        guard !flagged.isEmpty else { return }
        for dream in flagged {
            dream.updatedAt = .now
            dream.needsUpload = true
        }
        save()
        // Push now if signed in; otherwise the bumped timestamp means the next
        // reconcile will upload them as the newer copy.
        flagged.forEach(pushRemote)
    }

    /// Number of on-device dreams not yet tied to any account (guest dreams) — the
    /// ones a sign-in offers to merge into, or discard from, the account.
    func unownedLocalDreamCount() -> Int {
        let descriptor = FetchDescriptor<Dream>(predicate: #Predicate<Dream> { $0.userID == nil })
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    /// Pull the signed-in user's remote dreams and merge them with local ones.
    /// Safe to call on every sign-in / launch-while-signed-in.
    ///
    /// `claimLocalDreams` decides what happens to on-device guest dreams (those
    /// with no owner): a new account or an opt-in merge adopts them (`true`); a
    /// sign-in where the dreamer declined to merge drops them first (`false`).
    func reconcileWithRemote(claimLocalDreams: Bool = true) {
        guard let sync else { return }
        Task {
            guard let uid = await sync.currentUserID() else { return }
            // If the local store still holds a *different* account's data — e.g. a
            // sign-out whose wipe didn't complete — clear it before pulling this
            // account's, so one person's dreams never bleed into another's session.
            // A first sign-in from guest has no prior owner, so its dreams survive
            // here and get claimed by `merge` below.
            let last = UserDefaults.standard.string(forKey: Self.lastOwnerKey)
            if let last, last != uid.uuidString {
                wipeLocalData()
            }
            // Declined the merge on sign-in: drop the guest dreams up front so the
            // merge below can't adopt or upload them.
            if !claimLocalDreams {
                discardUnownedLocalDreams()
            }
            UserDefaults.standard.set(uid.uuidString, forKey: Self.lastOwnerKey)
            guard let remote = try? await sync.fetchAll(for: uid) else { return }
            await merge(remote: remote, userID: uid, sync: sync)
        }
    }

    /// Delete on-device dreams that were never tied to an account (guest dreams).
    /// They were never uploaded, so there's no remote row or tombstone to manage;
    /// any feed posts that referenced them are cleaned up defensively.
    private func discardUnownedLocalDreams() {
        let unowned = (try? context.fetch(
            FetchDescriptor<Dream>(predicate: #Predicate<Dream> { $0.userID == nil })
        )) ?? []
        guard !unowned.isEmpty else { return }
        for dream in unowned {
            let dreamID = dream.id
            let posts = (try? context.fetch(
                FetchDescriptor<FeedPost>(predicate: #Predicate<FeedPost> { $0.dreamID == dreamID })
            )) ?? []
            posts.forEach(context.delete)
            context.delete(dream)
        }
        save()
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
            unpublishRemote(dreamID: dreamID)
            return
        }

        if let post = existing.first {
            // Already shared — keep the snapshot in step with the dream's edits.
            post.title = dream.title
            post.dreamDescription = dream.entry
            post.mood = dream.mood.rawValue
            post.tags = dream.tags
            post.aiCategory = dream.aiCategory
            post.aiMeaning = dream.aiMeaning
            post.aiThemes = dream.aiThemes
            publishRemote(post)
        } else {
            let author = currentAuthor()
            let post = FeedPost(
                dreamID: dream.id,
                authorUsername: author.username,
                authorName: author.name,
                authorPhoto: author.photo,
                title: dream.title,
                dreamDescription: dream.entry,
                mood: dream.mood.rawValue,
                tags: dream.tags,
                aiCategory: dream.aiCategory,
                aiMeaning: dream.aiMeaning,
                aiThemes: dream.aiThemes
            )
            context.insert(post)
            publishRemote(post)
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

    /// Re-snapshot the signed-in dreamer's *own* feed posts (photo / name / handle)
    /// from the current profile, so editing your profile shows up on dreams you've
    /// already shared. Own posts are the ones backed by a local dream; everyone
    /// else's posts keep the author snapshot pulled from the server by `mergeFeed`.
    /// Cheap and idempotent — only writes when something actually changed.
    func refreshFeedAuthors() {
        let posts = (try? context.fetch(FetchDescriptor<FeedPost>())) ?? []
        guard !posts.isEmpty else { return }
        let myDreamIDs = Set(((try? context.fetch(FetchDescriptor<Dream>())) ?? []).map(\.id))
        let author = currentAuthor()
        var changed = false
        for post in posts where myDreamIDs.contains(post.dreamID) {
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

    // MARK: - Feed engagement (local-first, pushed to Supabase best-effort)

    /// Flip a post's like, keep the local count in step, and mirror to the server.
    func toggleLike(_ post: FeedPost) {
        post.isLiked.toggle()
        post.likeCount = max(0, post.likeCount + (post.isLiked ? 1 : -1))
        save()
        guard let feedSync else { return }
        let id = post.id, liked = post.isLiked
        Task { try? await feedSync.setLike(postID: id, liked: liked) }
    }

    /// Count one local impression for a post and record it remotely (the server
    /// dedupes per user, so a repeat view is a no-op there).
    func recordView(_ post: FeedPost) {
        post.viewCount += 1
        save()
        guard let feedSync else { return }
        let id = post.id
        Task { try? await feedSync.recordView(postID: id) }
    }

    /// Search public feed posts by title or dream text, for the feed's search
    /// screen. Returns records straight from the server (not local SwiftData) so
    /// results aren't limited to the cached feed. Best-effort — empty when the app
    /// is local-only, the query is blank, or the server can't be reached.
    func searchPosts(_ query: String, limit: Int = 30) async -> [FeedPostRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let feedSync, !trimmed.isEmpty else { return [] }
        return (try? await feedSync.searchPosts(query: trimmed, limit: limit)) ?? []
    }

    /// Add a comment locally and push it; bumps the post's comment count.
    @discardableResult
    func addComment(to post: FeedPost, text: String) -> Comment {
        let author = currentAuthor()
        let comment = Comment(
            postID: post.id,
            authorUsername: author.username,
            authorName: author.name,
            authorPhoto: author.photo,
            text: text
        )
        context.insert(comment)
        post.commentCount += 1
        save()

        if let feedSync {
            let id = comment.id, postID = post.id, text = comment.text
            let username = author.username, name = author.name
            Task { @MainActor in
                guard let uid = await feedSync.currentUserID() else { return }
                do {
                    try await feedSync.addComment(FeedCommentRecord(
                        id: id, postID: postID, authorID: uid,
                        authorUsername: username, authorName: name,
                        text: text, createdAt: .now
                    ))
                } catch FeedSyncError.rateLimited {
                    // Over the daily comment cap — undo the optimistic local insert
                    // so the journal matches the server, and tell the dreamer.
                    context.delete(comment)
                    post.commentCount = max(0, post.commentCount - 1)
                    save()
                    rateLimitNotice = String(
                        localized: "You can write up to 20 comments a day. Try again tomorrow."
                    )
                } catch {
                    // Other failures stay best-effort, as before.
                }
            }
        }
        return comment
    }

    func deleteComment(_ comment: Comment, on post: FeedPost) {
        let id = comment.id
        context.delete(comment)
        post.commentCount = max(0, post.commentCount - 1)
        save()
        guard let feedSync else { return }
        Task { try? await feedSync.deleteComment(id: id) }
    }

    /// Flip a comment's like, keep the local count in step, and mirror to the server.
    func toggleCommentLike(_ comment: Comment) {
        comment.isLiked.toggle()
        comment.likeCount = max(0, comment.likeCount + (comment.isLiked ? 1 : -1))
        save()
        guard let feedSync else { return }
        let id = comment.id, liked = comment.isLiked
        Task { try? await feedSync.setCommentLike(commentID: id, liked: liked) }
    }

    /// Report a feed post for review. There's nothing to mirror locally — the
    /// report is a server-side write — so this is a no-op without a backend.
    func reportPost(_ post: FeedPost, reason: ReportReason) {
        guard let feedSync else { return }
        let id = post.id, reason = reason.rawValue
        Task { @MainActor in
            do { try await feedSync.reportPost(postID: id, reason: reason) }
            catch FeedSyncError.rateLimited { noteReportLimit() }
            catch { }
        }
    }

    /// Report a comment for review. Server-side only, like `reportPost`.
    func reportComment(_ comment: Comment, reason: ReportReason) {
        guard let feedSync else { return }
        let id = comment.id, reason = reason.rawValue
        Task { @MainActor in
            do { try await feedSync.reportComment(commentID: id, reason: reason) }
            catch FeedSyncError.rateLimited { noteReportLimit() }
            catch { }
        }
    }

    private func noteReportLimit() {
        rateLimitNotice = String(
            localized: "You can report up to 5 posts a day. Try again tomorrow."
        )
    }

    /// Follow / unfollow a dreamer locally and remotely.
    func setFollow(username: String, following: Bool) {
        let descriptor = FetchDescriptor<Follow>(predicate: #Predicate<Follow> { $0.username == username })
        let existing = (try? context.fetch(descriptor)) ?? []
        if following, existing.isEmpty {
            context.insert(Follow(username: username))
        } else if !following {
            existing.forEach(context.delete)
        }
        save()
        guard let feedSync else { return }
        Task { @MainActor in
            if following {
                do {
                    try await feedSync.follow(username: username)
                } catch FeedSyncError.rateLimited {
                    // Over the daily follow cap — undo the optimistic local follow
                    // so it matches the server, and tell the dreamer.
                    unfollowLocally(username: username)
                    rateLimitNotice = String(
                        localized: "You can follow up to 50 accounts a day. Try again tomorrow."
                    )
                } catch {
                    // Other failures stay best-effort, as before.
                }
            } else {
                try? await feedSync.unfollow(username: username)
            }
        }
    }

    /// Undo a local follow when the server refused it (daily cap reached).
    private func unfollowLocally(username: String) {
        let descriptor = FetchDescriptor<Follow>(predicate: #Predicate<Follow> { $0.username == username })
        for follow in (try? context.fetch(descriptor)) ?? [] {
            context.delete(follow)
        }
        save()
    }

    // MARK: - Feed remote push / reconcile

    private func publishRemote(_ post: FeedPost) {
        guard let feedSync else { return }
        let id = post.id, dreamID = post.dreamID
        let username = post.authorUsername, name = post.authorName
        let title = post.title, description = post.dreamDescription, created = post.createdAt
        let mood = post.mood, tags = post.tags
        let aiCategory = post.aiCategory, aiMeaning = post.aiMeaning, aiThemes = post.aiThemes
        Task { @MainActor in
            guard let uid = await feedSync.currentUserID() else { return }
            do {
                try await feedSync.publish(FeedPostUpsert(
                    id: id, dreamID: dreamID, authorID: uid,
                    authorUsername: username, authorName: name,
                    title: title, dreamDescription: description, createdAt: created,
                    mood: mood, tags: tags,
                    aiCategory: aiCategory, aiMeaning: aiMeaning, aiThemes: aiThemes
                ))
            } catch FeedSyncError.rateLimited {
                // Over the daily publish cap. Only brand-new posts trip the trigger
                // (edits re-push an existing id), so unshare the dream locally to
                // match the server and tell the dreamer.
                unshareLocally(dreamID: dreamID)
                rateLimitNotice = String(
                    localized: "You can publish up to 3 dreams a day. Try again tomorrow."
                )
            } catch {
                // Other failures stay best-effort, as before.
            }
        }
    }

    /// Undo a local "share to feed" when the server refused the publish: drop the
    /// local FeedPost and flip the dream back to private so its visibility matches
    /// what actually reached the feed.
    private func unshareLocally(dreamID: UUID) {
        let postDescriptor = FetchDescriptor<FeedPost>(predicate: #Predicate<FeedPost> { $0.dreamID == dreamID })
        for post in (try? context.fetch(postDescriptor)) ?? [] {
            context.delete(post)
        }
        let dreamDescriptor = FetchDescriptor<Dream>(predicate: #Predicate<Dream> { $0.id == dreamID })
        if let dream = (try? context.fetch(dreamDescriptor))?.first {
            dream.isPublic = false
        }
        save()
    }

    private func unpublishRemote(dreamID: UUID) {
        guard let feedSync else { return }
        Task { try? await feedSync.unpublish(dreamID: dreamID) }
    }

    /// Pull the shared feed into the local SwiftData cache so the existing
    /// `@Query`-driven feed UI shows everyone's posts. Server counts win; the
    /// local author photo is preserved for our own posts. Safe to call on launch /
    /// sign-in and when the feed appears.
    func reconcileFeed() {
        guard let feedSync else { return }
        Task {
            // A *failed* fetch must not be treated as "the feed is empty" — that
            // would make mergeFeed delete every other dreamer's cached post and
            // wipe the local follow set. Only merge when the fetch succeeds; a
            // genuinely empty feed still returns [] and reconciles normally.
            guard let remotePosts = try? await feedSync.fetchFeed(limit: 200) else { return }
            let likedIDs = (try? await feedSync.likedPostIDs()) ?? []
            let followed = (try? await feedSync.followedUsernames()) ?? []
            await mergeFeed(remote: remotePosts, liked: Set(likedIDs), followed: followed)
        }
    }

    private func mergeFeed(remote: [FeedPostRecord], liked: Set<UUID>, followed: [String]) async {
        let locals = (try? context.fetch(FetchDescriptor<FeedPost>())) ?? []
        var localByID = Dictionary(locals.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let remoteIDs = Set(remote.map(\.id))

        for record in remote {
            if let post = localByID[record.id] {
                post.title = record.title
                post.dreamDescription = record.dreamDescription
                post.authorUsername = record.authorUsername
                post.authorName = record.authorName
                post.likeCount = record.likeCount
                post.viewCount = record.viewCount
                post.commentCount = record.commentCount
                post.isLiked = liked.contains(record.id)
                post.mood = record.mood
                post.tags = record.tags ?? []
                post.aiCategory = record.aiCategory
                post.aiMeaning = record.aiMeaning
                post.aiThemes = record.aiThemes ?? []
            } else {
                let post = FeedPost(
                    id: record.id,
                    dreamID: record.dreamID,
                    authorUsername: record.authorUsername,
                    authorName: record.authorName,
                    title: record.title,
                    dreamDescription: record.dreamDescription,
                    createdAt: record.createdAt,
                    likeCount: record.likeCount,
                    isLiked: liked.contains(record.id),
                    commentCount: record.commentCount,
                    viewCount: record.viewCount,
                    mood: record.mood,
                    tags: record.tags ?? [],
                    aiCategory: record.aiCategory,
                    aiMeaning: record.aiMeaning,
                    aiThemes: record.aiThemes ?? []
                )
                context.insert(post)
                localByID[record.id] = post
            }
        }

        // Drop *others'* local posts that no longer exist remotely. Our own posts
        // are managed locally by `syncFeedPost`, and a fresh one may not have
        // round-tripped to the server yet, so never delete those here.
        let me = currentAuthor().username.lowercased()
        for post in locals where !remoteIDs.contains(post.id) && post.authorUsername.lowercased() != me {
            context.delete(post)
        }

        // Mirror the follow set locally.
        let followedSet = Set(followed.map { $0.lowercased() })
        let localFollows = (try? context.fetch(FetchDescriptor<Follow>())) ?? []
        for follow in localFollows where !followedSet.contains(follow.username.lowercased()) {
            context.delete(follow)
        }
        let existingLocal = Set(localFollows.map { $0.username.lowercased() })
        for username in followed where !existingLocal.contains(username.lowercased()) {
            context.insert(Follow(username: username))
        }

        save()
    }

    /// Pull a post's comments into the local cache so the comments sheet shows
    /// everyone's, not just this device's.
    func reconcileComments(postID: UUID) {
        guard let feedSync else { return }
        Task {
            async let remote = (try? await feedSync.fetchComments(postID: postID)) ?? []
            async let liked = (try? await feedSync.likedCommentIDs(postID: postID)) ?? []
            await mergeComments(remote: remote, liked: Set(liked), postID: postID)
        }
    }

    private func mergeComments(remote: [FeedCommentRecord], liked: Set<UUID>, postID: UUID) async {
        let descriptor = FetchDescriptor<Comment>(predicate: #Predicate<Comment> { $0.postID == postID })
        let locals = (try? context.fetch(descriptor)) ?? []
        var byID = Dictionary(locals.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let remoteIDs = Set(remote.map(\.id))

        for record in remote {
            if let comment = byID[record.id] {
                comment.text = record.text
                comment.authorUsername = record.authorUsername
                comment.authorName = record.authorName
                comment.likeCount = record.likeCount
                comment.isLiked = liked.contains(record.id)
            } else {
                let comment = Comment(
                    id: record.id,
                    postID: record.postID,
                    authorUsername: record.authorUsername,
                    authorName: record.authorName,
                    text: record.text,
                    createdAt: record.createdAt,
                    likeCount: record.likeCount,
                    isLiked: liked.contains(record.id)
                )
                context.insert(comment)
                byID[record.id] = comment
            }
        }

        // Remove others' comments deleted remotely; keep our own (may be mid-push).
        let me = currentAuthor().username.lowercased()
        for comment in locals where !remoteIDs.contains(comment.id) && comment.authorUsername.lowercased() != me {
            context.delete(comment)
        }

        save()
    }

    // MARK: - Notifications

    /// Pull the dreamer's activity (likes/comments on their posts) into the local
    /// cache so the bell badge and Activity screen reflect the server. Safe to call
    /// on launch / sign-in and when the Profile tab appears.
    func reconcileNotifications() {
        guard let feedSync else { return }
        Task {
            let remote = (try? await feedSync.fetchNotifications(limit: 100)) ?? []
            await mergeNotifications(remote: remote)
        }
    }

    private func mergeNotifications(remote: [FeedNotificationRecord]) async {
        let locals = (try? context.fetch(FetchDescriptor<AppNotification>())) ?? []
        var byID = Dictionary(locals.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let remoteIDs = Set(remote.map(\.id))

        for record in remote {
            if let note = byID[record.id] {
                note.isRead = record.readAt != nil
                note.postTitle = record.postTitle
                note.actorUsername = record.actorUsername
                note.actorName = record.actorName
                note.commentText = record.commentText
            } else {
                let note = AppNotification(
                    id: record.id,
                    type: record.type,
                    actorUsername: record.actorUsername,
                    actorName: record.actorName,
                    postID: record.postID,
                    postTitle: record.postTitle,
                    commentText: record.commentText,
                    createdAt: record.createdAt,
                    isRead: record.readAt != nil
                )
                context.insert(note)
                byID[record.id] = note
            }
        }

        // The server is the source of truth: drop locals it no longer returns
        // (e.g. a like was withdrawn, or a comment deleted).
        for note in locals where !remoteIDs.contains(note.id) {
            context.delete(note)
        }

        save()
    }

    /// Mark every notification read locally and clear the server's unread flags.
    func markNotificationsRead() {
        let unread = (try? context.fetch(
            FetchDescriptor<AppNotification>(predicate: #Predicate { !$0.isRead })
        )) ?? []
        guard !unread.isEmpty else { return }
        unread.forEach { $0.isRead = true }
        save()
        guard let feedSync else { return }
        Task { try? await feedSync.markAllNotificationsRead() }
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
            isPublic: isPublic,
            isLucid: isLucid,
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
            isPublic: isPublic ?? false,
            isLucid: isLucid ?? false,
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
        dream.isPublic = isPublic ?? false
        dream.isLucid = isLucid ?? false
        dream.aiCategory = aiCategory
        dream.aiMeaning = aiMeaning
        dream.aiThemes = aiThemes ?? []
        dream.updatedAt = updatedAt
    }
}

// Not wrapped in `#if DEBUG`: the `#Preview` blocks that use this are compiled in
// every configuration (including the Release/archive build), so PreviewData must
// be too. It's never invoked in the shipped app — previews only run in Xcode.
@MainActor
enum PreviewData {
    /// An in-memory container seeded with samples, for SwiftUI previews.
    static let container: ModelContainer = {
        let container = try! ModelContainer(
            for: Dream.self, DeletedDream.self, FeedPost.self, Follow.self, Comment.self, AppNotification.self,
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
