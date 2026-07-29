//
//  FeedSyncResilienceTests.swift
//  HalfLightTests
//
//  One rule, three places: a *failed* fetch is not an empty result.
//
//  Every reconcile in `DreamStore` merges a server snapshot into the local cache
//  and then deletes whatever the snapshot didn't mention. That's correct for a
//  genuinely empty response and destructive for a failed one — the difference is
//  invisible once an error has been flattened into `[]`. These tests hold the
//  line for the feed, its like state, the follow list, and activity.
//
//  (`CommentSyncTests` covers the same rule for comment threads, which is where
//  the problem first showed up as "the post says 3 comments but shows none".)
//

import XCTest
import SwiftData
@testable import HalfLight

@MainActor
final class FeedSyncResilienceTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUp() {
        super.setUp()
        container = try! ModelContainer(
            for: Dream.self, DeletedDream.self, FeedPost.self, Follow.self,
            Comment.self, AppNotification.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        UserDefaults.standard.set("dreamer", forKey: "userUsername")
        UserDefaults.standard.set("Dreamer", forKey: "userName")
    }

    override func tearDown() {
        container = nil
        UserDefaults.standard.removeObject(forKey: "userUsername")
        UserDefaults.standard.removeObject(forKey: "userName")
        super.tearDown()
    }

    /// `reconcileFeed` fires a detached Task, so drive it and let that Task land.
    private func reconcileFeed(_ sync: ResilienceStubSync) async {
        DreamStore(context: context, feedSync: sync).reconcileFeed()
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(60))
    }

    private func reconcileNotifications(_ sync: ResilienceStubSync) async {
        DreamStore(context: context, feedSync: sync).reconcileNotifications()
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(60))
    }

    private func postRecord(id: UUID, author: String = "someone_else") -> FeedPostRecord {
        FeedPostRecord(
            id: id, dreamID: UUID(), authorID: UUID(),
            authorUsername: author, authorName: author.capitalized,
            title: "A dream", dreamDescription: "…", createdAt: .now,
            likeCount: 1, viewCount: 0, commentCount: 0, mood: "vivid", tags: []
        )
    }

    // MARK: Like state

    /// The likes lookup is its own request. If only it fails, every post must not
    /// silently lose its heart.
    func testFailedLikeLookupDoesNotUnlikeEverything() async {
        let id = UUID()
        let post = FeedPost(
            id: id, dreamID: UUID(), authorUsername: "someone_else",
            authorName: "Someone Else", title: "A dream", dreamDescription: "…",
            likeCount: 1, isLiked: true
        )
        context.insert(post)
        try? context.save()

        let sync = ResilienceStubSync()
        sync.feed = [postRecord(id: id)]
        sync.likedError = StubSyncError.offline

        await reconcileFeed(sync)

        XCTAssertTrue(post.isLiked, "A failed likes lookup must not clear the heart")
    }

    func testLikeStateStillAppliesWhenTheLookupSucceeds() async {
        let id = UUID()
        let post = FeedPost(
            id: id, dreamID: UUID(), authorUsername: "someone_else",
            authorName: "Someone Else", title: "A dream", dreamDescription: "…",
            likeCount: 1, isLiked: true
        )
        context.insert(post)
        try? context.save()

        let sync = ResilienceStubSync()
        sync.feed = [postRecord(id: id)]
        sync.liked = []   // a real answer: you've unliked it elsewhere

        await reconcileFeed(sync)

        XCTAssertFalse(post.isLiked)
    }

    // MARK: Follow list

    /// A failed follow lookup used to delete the dreamer's entire follow list.
    func testFailedFollowLookupDoesNotWipeTheFollowList() async {
        context.insert(Follow(username: "friend_one"))
        context.insert(Follow(username: "friend_two"))
        try? context.save()

        let sync = ResilienceStubSync()
        sync.feed = []
        sync.followedError = StubSyncError.offline

        await reconcileFeed(sync)

        let follows = (try? context.fetch(FetchDescriptor<Follow>())) ?? []
        XCTAssertEqual(follows.count, 2, "A failed follow lookup must not unfollow anyone")
    }

    /// A real answer still reconciles: unfollowed elsewhere means gone here.
    func testSuccessfulFollowLookupStillReconciles() async {
        context.insert(Follow(username: "friend_one"))
        context.insert(Follow(username: "friend_two"))
        try? context.save()

        let sync = ResilienceStubSync()
        sync.feed = []
        sync.followed = ["friend_one"]

        await reconcileFeed(sync)

        let follows = (try? context.fetch(FetchDescriptor<Follow>())) ?? []
        XCTAssertEqual(follows.map(\.username), ["friend_one"])
    }

    // MARK: Activity

    func testFailedNotificationFetchKeepsTheActivityScreen() async {
        context.insert(AppNotification(
            id: UUID(), type: "like", actorUsername: "friend", actorName: "Friend",
            postID: UUID(), postTitle: "A dream", commentText: nil,
            createdAt: .now, isRead: false
        ))
        try? context.save()

        let sync = ResilienceStubSync()
        sync.notificationsError = StubSyncError.offline

        await reconcileNotifications(sync)

        let notes = (try? context.fetch(FetchDescriptor<AppNotification>())) ?? []
        XCTAssertEqual(notes.count, 1, "A failed fetch must not blank Activity")
    }

    func testSuccessfulEmptyNotificationFetchStillClears() async {
        context.insert(AppNotification(
            id: UUID(), type: "like", actorUsername: "friend", actorName: "Friend",
            postID: UUID(), postTitle: "A dream", commentText: nil,
            createdAt: .now, isRead: false
        ))
        try? context.save()

        let sync = ResilienceStubSync()
        sync.notifications = []   // a real answer: nothing there anymore

        await reconcileNotifications(sync)

        let notes = (try? context.fetch(FetchDescriptor<AppNotification>())) ?? []
        XCTAssertTrue(notes.isEmpty)
    }
}

// MARK: - Stub

enum StubSyncError: Error { case offline }

/// A `FeedSyncing` whose every call can be made to fail independently, so each
/// request's failure mode can be tested on its own.
final class ResilienceStubSync: FeedSyncing, @unchecked Sendable {
    var feed: [FeedPostRecord] = []
    var feedError: Error?
    var liked: [UUID] = []
    var likedError: Error?
    var followed: [String] = []
    var followedError: Error?
    var notifications: [FeedNotificationRecord] = []
    var notificationsError: Error?

    func currentUserID() async -> UUID? { UUID() }

    func fetchFeed(limit: Int) async throws -> [FeedPostRecord] {
        if let feedError { throw feedError }
        return feed
    }

    func likedPostIDs() async throws -> [UUID] {
        if let likedError { throw likedError }
        return liked
    }

    func followedUsernames() async throws -> [String] {
        if let followedError { throw followedError }
        return followed
    }

    func fetchNotifications(limit: Int) async throws -> [FeedNotificationRecord] {
        if let notificationsError { throw notificationsError }
        return notifications
    }

    // Unused here.
    func publish(_ post: FeedPostUpsert) async throws {}
    func unpublish(dreamID: UUID) async throws {}
    func searchPosts(query: String, limit: Int) async throws -> [FeedPostRecord] { [] }
    func setLike(postID: UUID, liked: Bool) async throws {}
    func recordView(postID: UUID) async throws {}
    func fetchComments(postID: UUID) async throws -> [FeedCommentRecord] { [] }
    func addComment(_ comment: FeedCommentRecord) async throws {}
    func deleteComment(id: UUID) async throws {}
    func likedCommentIDs(postID: UUID) async throws -> [UUID] { [] }
    func setCommentLike(commentID: UUID, liked: Bool) async throws {}
    func follow(username: String) async throws {}
    func unfollow(username: String) async throws {}
    func markAllNotificationsRead() async throws {}
    func reportPost(postID: UUID, reason: String) async throws {}
    func reportComment(commentID: UUID, reason: String) async throws {}
}
