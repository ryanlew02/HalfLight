//
//  FeedRankerTests.swift
//  HalfLightTests
//
//  Verifies the feed ordering mirrors the comment ordering's shape: it leads with
//  the most-engaging / trending posts (here, like-per-view conversion), but still
//  mixes in fresh, barely-seen posts that are on the rise (see `CommentRankerTests`).
//

import XCTest
@testable import HalfLight__AI_Dream_Journal_

@MainActor
final class FeedRankerTests: XCTestCase {

    /// Fixed reference time so age-based signals are deterministic.
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    private func post(
        likes: Int,
        views: Int,
        ageHours: Double,
        author: String = "dreamer"
    ) -> FeedPost {
        FeedPost(
            dreamID: UUID(),
            authorUsername: author,
            authorName: "Dreamer",
            title: "A dream",
            dreamDescription: "...",
            createdAt: now.addingTimeInterval(-ageHours * 3600),
            likeCount: likes,
            isLiked: false,
            commentCount: 0,
            viewCount: views
        )
    }

    private func ranked(
        _ posts: [FeedPost],
        following: Set<String> = []
    ) -> [FeedPost] {
        FeedRanker.rank(posts: posts, dreamsByID: [:], followedUsernames: following, now: now)
    }

    // MARK: Trending (conversion)

    /// Among posts seen equally often, the one that converts views into likes the
    /// hardest leads — the feed's "trending" signal.
    func testHigherConversionLeads() {
        let strong = post(likes: 50, views: 100, ageHours: 10)
        let weak = post(likes: 10, views: 100, ageHours: 10)

        let order = ranked([weak, strong])

        XCTAssertEqual(order.first?.id, strong.id)
    }

    /// "On the rise": same like total, but the post that earned them off far fewer
    /// views (a higher conversion rate) outranks the one that needed a huge audience.
    func testOnTheRiseBeatsWidelySeen() {
        let rising = post(likes: 8, views: 12, ageHours: 3)
        let saturated = post(likes: 8, views: 1000, ageHours: 3)

        let order = ranked([saturated, rising])

        XCTAssertEqual(order.first?.id, rising.id)
    }

    // MARK: New & quiet (mixed in)

    /// With no engagement anywhere, the fresh, barely-seen post surfaces ahead of
    /// an old, heavily-shown one — freshness is mixed into the ordering.
    func testFreshAndQuietSurfaces() {
        let freshQuiet = post(likes: 0, views: 0, ageHours: 0.1)
        let oldSeen = post(likes: 0, views: 1000, ageHours: 200)

        let order = ranked([oldSeen, freshQuiet])

        XCTAssertEqual(order.first?.id, freshQuiet.id)
    }

    // MARK: Following

    /// Following the author is a tie-breaking boost when engagement is otherwise equal.
    func testFollowingBoost() {
        let followed = post(likes: 10, views: 100, ageHours: 10, author: "friend")
        let stranger = post(likes: 10, views: 100, ageHours: 10, author: "stranger")

        let order = ranked([stranger, followed], following: ["friend"])

        XCTAssertEqual(order.first?.id, followed.id)
    }

    // MARK: Edge cases

    func testEmptyReturnsEmpty() {
        XCTAssertTrue(ranked([]).isEmpty)
    }

    func testRankingPreservesTheSet() {
        let posts = [
            post(likes: 2, views: 10, ageHours: 1),
            post(likes: 40, views: 100, ageHours: 50),
            post(likes: 0, views: 0, ageHours: 0.2),
            post(likes: 8, views: 1000, ageHours: 300),
        ]
        let order = ranked(posts)
        XCTAssertEqual(Set(order.map(\.id)), Set(posts.map(\.id)))
        XCTAssertEqual(order.count, posts.count)
    }
}
