//
//  SearchPostCacheTests.swift
//  HalfLightTests
//
//  Covers `DreamStore.cachePost` — the bridge that lets a dream opened from
//  search be liked and commented on. Liking/commenting need a local `FeedPost`,
//  but a searched post may be far older than the feed window, so the cached copy
//  is flagged `isSearchResult` to keep it out of the feed's query without
//  disturbing the posts that are genuinely in it.
//

import XCTest
import SwiftData
@testable import HalfLight

@MainActor
final class SearchPostCacheTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUp() {
        super.setUp()
        container = try! ModelContainer(
            for: Dream.self, DeletedDream.self, FeedPost.self, Follow.self,
            Comment.self, AppNotification.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        UserDefaults.standard.set("Dreamer", forKey: "userName")
        UserDefaults.standard.set("dreamer", forKey: "userUsername")
    }

    override func tearDown() {
        container = nil
        UserDefaults.standard.removeObject(forKey: "userName")
        UserDefaults.standard.removeObject(forKey: "userUsername")
        super.tearDown()
    }

    private func record(
        id: UUID = UUID(),
        author: String = "someone_else",
        title: String = "A shared dream",
        likeCount: Int = 4,
        commentCount: Int = 2
    ) -> FeedPostRecord {
        FeedPostRecord(
            id: id,
            dreamID: UUID(),
            authorID: UUID(),
            authorUsername: author,
            authorName: author.capitalized,
            title: title,
            dreamDescription: "I was flying over a city.",
            createdAt: .now,
            likeCount: likeCount,
            viewCount: 9,
            commentCount: commentCount,
            mood: "vivid",
            tags: ["flying"]
        )
    }

    private func cachedPosts() -> [FeedPost] {
        (try? context.fetch(FetchDescriptor<FeedPost>())) ?? []
    }

    // MARK: Caching

    /// The core of the feature: a searched post becomes a real local post, so the
    /// detail screen has something to like and comment on.
    func testCachingASearchedPostMakesItLikeable() {
        let store = DreamStore(context: context)
        let post = store.cachePost(record(title: "Lighthouse"))

        XCTAssertEqual(post.title, "Lighthouse")
        XCTAssertEqual(post.likeCount, 4)
        XCTAssertEqual(post.commentCount, 2)
        XCTAssertEqual(cachedPosts().count, 1)

        store.toggleLike(post)
        XCTAssertTrue(post.isLiked)
        XCTAssertEqual(post.likeCount, 5)
    }

    /// It's flagged so the feed's query can exclude it — a search hit shouldn't
    /// silently splice an old post into the feed.
    func testNewlyCachedPostIsFlaggedAsSearchOnly() {
        let post = DreamStore(context: context).cachePost(record())
        XCTAssertTrue(post.isSearchResult)
    }

    /// Caching is idempotent: finding the same post twice doesn't duplicate it.
    func testCachingTwiceReusesTheSamePost() {
        let store = DreamStore(context: context)
        let id = UUID()

        let first = store.cachePost(record(id: id, title: "Original"))
        let second = store.cachePost(record(id: id, title: "Retitled"))

        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(cachedPosts().count, 1)
        XCTAssertEqual(second.title, "Retitled")
    }

    /// A post already in the feed keeps its like state and its place in the feed
    /// when it also turns up in search.
    func testCachingAFeedPostPreservesLikeStateAndFeedVisibility() {
        let id = UUID()
        let existing = FeedPost(
            id: id, dreamID: UUID(), authorUsername: "someone_else", authorName: "Someone Else",
            title: "From the feed", dreamDescription: "…", likeCount: 4, isLiked: true
        )
        context.insert(existing)
        try? context.save()

        let cached = DreamStore(context: context).cachePost(record(id: id, title: "From the feed"))

        XCTAssertTrue(cached.isLiked, "Local like state is the truth; search results don't carry it")
        XCTAssertFalse(cached.isSearchResult, "A post already in the feed must stay in the feed")
        XCTAssertEqual(cachedPosts().count, 1)
    }

    // MARK: Comments on a searched post

    func testCommentingOnASearchedPostBumpsItsCount() {
        let store = DreamStore(context: context)
        let post = store.cachePost(record(commentCount: 2))

        store.addComment(to: post, text: "I had a dream like this")

        XCTAssertEqual(post.commentCount, 3)
        let comments = (try? context.fetch(FetchDescriptor<Comment>())) ?? []
        XCTAssertEqual(comments.map(\.text), ["I had a dream like this"])
        XCTAssertEqual(comments.first?.postID, post.id)
    }
}
