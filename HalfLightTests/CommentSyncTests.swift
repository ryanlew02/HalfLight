//
//  CommentSyncTests.swift
//  HalfLightTests
//
//  Covers `DreamStore.reconcileComments` — the pull that fills the comments sheet
//  from the server. The sheet renders the *local* SwiftData cache, so anything
//  this merge drops disappears from the UI; the tests below pin down what a
//  failed fetch is and isn't allowed to do to that cache.
//

import XCTest
import SwiftData
@testable import HalfLight

@MainActor
final class CommentSyncTests: XCTestCase {

    // MARK: Fixtures

    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    private let postID = UUID()
    private let me = "dreamer"

    override func setUp() {
        super.setUp()
        container = try! ModelContainer(
            for: Dream.self, DeletedDream.self, FeedPost.self, Follow.self,
            Comment.self, AppNotification.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        // `currentAuthor()` reads these defaults to decide which comments are ours.
        UserDefaults.standard.set("Dreamer", forKey: "userName")
        UserDefaults.standard.set(me, forKey: "userUsername")
    }

    override func tearDown() {
        container = nil
        UserDefaults.standard.removeObject(forKey: "userName")
        UserDefaults.standard.removeObject(forKey: "userUsername")
        super.tearDown()
    }

    private func store(_ sync: StubFeedSync) -> DreamStore {
        DreamStore(context: context, feedSync: sync)
    }

    @discardableResult
    private func seedComment(
        id: UUID = UUID(),
        author: String = "someone_else",
        text: String = "a cached comment",
        isLiked: Bool = false,
        likeCount: Int = 0
    ) -> Comment {
        let comment = Comment(
            id: id,
            postID: postID,
            authorUsername: author,
            authorName: author.capitalized,
            text: text,
            likeCount: likeCount,
            isLiked: isLiked
        )
        context.insert(comment)
        try? context.save()
        return comment
    }

    private func record(
        id: UUID = UUID(),
        author: String = "someone_else",
        text: String = "a server comment",
        likeCount: Int = 0
    ) -> FeedCommentRecord {
        FeedCommentRecord(
            id: id,
            postID: postID,
            authorID: UUID(),
            authorUsername: author,
            authorName: author.capitalized,
            text: text,
            createdAt: .now,
            likeCount: likeCount
        )
    }

    private func cachedComments() -> [Comment] {
        let postID = self.postID
        let descriptor = FetchDescriptor<Comment>(
            predicate: #Predicate<Comment> { $0.postID == postID }
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: The reported glitch — comments vanish on a failed fetch

    /// The bug: a transient fetch failure must not empty the sheet. Before the
    /// fix, a thrown `fetchComments` was swallowed into `[]` and the merge then
    /// deleted every cached comment, so a post with comments showed "No comments
    /// yet" until the next successful pull.
    func testCachedCommentsSurviveAFailedFetch() async {
        seedComment(text: "first")
        seedComment(text: "second")

        let sync = StubFeedSync()
        sync.commentsError = StubError.offline

        let loaded = await store(sync).reconcileComments(postID: postID)

        XCTAssertFalse(loaded, "A failed fetch must report that no snapshot landed")
        XCTAssertEqual(cachedComments().count, 2, "A failed fetch must not clear the cache")
    }

    /// Same failure, seen the way the sheet sees it: the post still claims
    /// comments, so the view must have something to show.
    func testPostWithCommentsIsNotEmptyAfterAFailedFetch() async {
        seedComment()
        let sync = StubFeedSync()
        sync.commentsError = StubError.offline

        _ = await store(sync).reconcileComments(postID: postID)

        XCTAssertFalse(cachedComments().isEmpty)
    }

    // MARK: Happy path

    func testSuccessfulFetchPopulatesTheCache() async {
        let sync = StubFeedSync()
        sync.comments = [record(text: "hello"), record(text: "there")]

        let loaded = await store(sync).reconcileComments(postID: postID)

        XCTAssertTrue(loaded)
        XCTAssertEqual(Set(cachedComments().map(\.text)), ["hello", "there"])
    }

    /// A second pull updates rows in place rather than duplicating them.
    func testRepeatedFetchDoesNotDuplicate() async {
        let sync = StubFeedSync()
        let id = UUID()
        sync.comments = [record(id: id, text: "original")]
        let store = store(sync)

        _ = await store.reconcileComments(postID: postID)
        sync.comments = [record(id: id, text: "edited", likeCount: 3)]
        _ = await store.reconcileComments(postID: postID)

        let cached = cachedComments()
        XCTAssertEqual(cached.count, 1)
        XCTAssertEqual(cached.first?.text, "edited")
        XCTAssertEqual(cached.first?.likeCount, 3)
    }

    /// The sweep still has to work: a comment deleted on the server goes away.
    func testRemotelyDeletedCommentIsRemoved() async {
        let kept = UUID()
        seedComment(id: kept, text: "kept")
        seedComment(text: "deleted remotely")

        let sync = StubFeedSync()
        sync.comments = [record(id: kept, text: "kept")]

        _ = await store(sync).reconcileComments(postID: postID)

        XCTAssertEqual(cachedComments().map(\.text), ["kept"])
    }

    /// A genuinely empty thread does clear the cache — that's a real answer from
    /// the server, unlike a failure.
    func testEmptyServerResponseClearsOthersComments() async {
        seedComment()
        let sync = StubFeedSync()
        sync.comments = []

        _ = await store(sync).reconcileComments(postID: postID)

        XCTAssertTrue(cachedComments().isEmpty)
    }

    /// Our own comment may still be mid-push, so the sweep leaves it alone.
    func testOwnPendingCommentIsKept() async {
        seedComment(author: me, text: "just posted")
        let sync = StubFeedSync()
        sync.comments = []

        _ = await store(sync).reconcileComments(postID: postID)

        XCTAssertEqual(cachedComments().map(\.text), ["just posted"])
    }

    /// A comment posted while offline is still in the cache after the failed
    /// reconcile that follows, so the dreamer sees their own comment.
    func testOwnCommentPostedOfflineStillShows() async {
        let post = FeedPost(
            id: postID, dreamID: UUID(), authorUsername: me, authorName: "Dreamer",
            title: "A dream", dreamDescription: "…"
        )
        context.insert(post)
        let sync = StubFeedSync()
        sync.commentsError = StubError.offline
        let store = store(sync)

        store.addComment(to: post, text: "posted offline")
        _ = await store.reconcileComments(postID: postID)

        XCTAssertEqual(cachedComments().map(\.text), ["posted offline"])
    }

    // MARK: Like state

    func testLikedIDsAreAppliedOnSuccess() async {
        let id = UUID()
        let sync = StubFeedSync()
        sync.comments = [record(id: id)]
        sync.likedCommentIDs = [id]

        _ = await store(sync).reconcileComments(postID: postID)

        XCTAssertEqual(cachedComments().first?.isLiked, true)
    }

    func testUnlikedRemotelyClearsTheLocalHeart() async {
        let id = UUID()
        seedComment(id: id, isLiked: true, likeCount: 1)
        let sync = StubFeedSync()
        sync.comments = [record(id: id, likeCount: 0)]
        sync.likedCommentIDs = []

        _ = await store(sync).reconcileComments(postID: postID)

        XCTAssertEqual(cachedComments().first?.isLiked, false)
    }

    /// The likes lookup is a separate request. If only *it* fails, the comments
    /// still render — but every heart must not silently empty out.
    func testLikeStateSurvivesAFailedLikesFetch() async {
        let id = UUID()
        seedComment(id: id, isLiked: true, likeCount: 1)
        let sync = StubFeedSync()
        sync.comments = [record(id: id, likeCount: 1)]
        sync.likesError = StubError.offline

        _ = await store(sync).reconcileComments(postID: postID)

        XCTAssertEqual(cachedComments().first?.isLiked, true, "A failed likes fetch must not unlike")
    }
}

// MARK: - Stub backend

private enum StubError: Error { case offline }

/// A `FeedSyncing` that answers from canned values and can be told to throw,
/// standing in for Supabase.
private final class StubFeedSync: FeedSyncing, @unchecked Sendable {
    var comments: [FeedCommentRecord] = []
    var commentsError: Error?
    var likedCommentIDs: [UUID] = []
    var likesError: Error?

    func currentUserID() async -> UUID? { UUID() }

    func fetchComments(postID: UUID) async throws -> [FeedCommentRecord] {
        if let commentsError { throw commentsError }
        return comments
    }

    func likedCommentIDs(postID: UUID) async throws -> [UUID] {
        if let likesError { throw likesError }
        return likedCommentIDs
    }

    // Unused by these tests.
    func publish(_ post: FeedPostUpsert) async throws {}
    func unpublish(dreamID: UUID) async throws {}
    func fetchFeed(limit: Int) async throws -> [FeedPostRecord] { [] }
    func searchPosts(query: String, limit: Int) async throws -> [FeedPostRecord] { [] }
    func likedPostIDs() async throws -> [UUID] { [] }
    func setLike(postID: UUID, liked: Bool) async throws {}
    func recordView(postID: UUID) async throws {}
    func addComment(_ comment: FeedCommentRecord) async throws {}
    func deleteComment(id: UUID) async throws {}
    func setCommentLike(commentID: UUID, liked: Bool) async throws {}
    func followedUsernames() async throws -> [String] { [] }
    func follow(username: String) async throws {}
    func unfollow(username: String) async throws {}
    func fetchNotifications(limit: Int) async throws -> [FeedNotificationRecord] { [] }
    func markAllNotificationsRead() async throws {}
    func reportPost(postID: UUID, reason: String) async throws {}
    func reportComment(commentID: UUID, reason: String) async throws {}
}
