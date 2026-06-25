//
//  CommentRankerTests.swift
//  HalfLightTests
//
//  Verifies the comment ordering: it leads with the most-liked / trending
//  comments, but still mixes in brand-new and on-the-rise ones — the same shape
//  as `FeedRanker` (see `FeedRankerTests`).
//

import XCTest
@testable import HalfLight__AI_Dream_Journal_

@MainActor
final class CommentRankerTests: XCTestCase {

    /// Fixed reference time so age-based signals are deterministic.
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    private func comment(likes: Int, ageHours: Double) -> Comment {
        Comment(
            postID: UUID(),
            authorUsername: "dreamer",
            authorName: "Dreamer",
            text: "a comment",
            createdAt: now.addingTimeInterval(-ageHours * 3600),
            likeCount: likes
        )
    }

    private func ranked(_ comments: [Comment]) -> [Comment] {
        CommentRanker.rank(comments, now: now)
    }

    // MARK: Top (likes)

    /// Among comments of the same age, the most-liked comes first.
    func testMostLikedLeadsAmongSameAge() {
        let none = comment(likes: 0, ageHours: 24)
        let some = comment(likes: 5, ageHours: 24)
        let lots = comment(likes: 50, ageHours: 24)

        let order = ranked([none, some, lots])

        XCTAssertEqual(order.map(\.id), [lots.id, some.id, none.id])
    }

    /// Likes/trending dominate: a heavily-liked older comment still outranks a
    /// brand-new comment with no likes (freshness is only "a bit" mixed in).
    func testPopularStillBeatsBrandNew() {
        let popularOld = comment(likes: 100, ageHours: 100)
        let freshEmpty = comment(likes: 0, ageHours: 0)

        let order = ranked([freshEmpty, popularOld])

        XCTAssertEqual(order.first?.id, popularOld.id)
    }

    // MARK: New / on the rise (mixed in)

    /// With no likes anywhere, the newest comment surfaces first — proof that
    /// freshness is mixed into the ordering.
    func testFreshSurfacesWhenNothingIsLiked() {
        let old = comment(likes: 0, ageHours: 100)
        let new = comment(likes: 0, ageHours: 0.1)

        let order = ranked([old, new])

        XCTAssertEqual(order.first?.id, new.id)
    }

    /// "On the rise": two comments with the *same* like count rank by velocity —
    /// the one that earned them faster (younger) comes first.
    func testOnTheRiseBeatsSlowAccumulator() {
        let rising = comment(likes: 5, ageHours: 1)     // 5 likes in an hour
        let stale = comment(likes: 5, ageHours: 240)    // 5 likes over ten days

        let order = ranked([stale, rising])

        XCTAssertEqual(order.first?.id, rising.id)
    }

    // MARK: Edge cases

    func testEmptyReturnsEmpty() {
        XCTAssertTrue(ranked([]).isEmpty)
    }

    func testSingleIsUnchanged() {
        let only = comment(likes: 3, ageHours: 5)
        XCTAssertEqual(ranked([only]).map(\.id), [only.id])
    }

    /// Ranking is a pure reordering — it never drops or duplicates comments.
    func testRankingPreservesTheSet() {
        let comments = [
            comment(likes: 2, ageHours: 1),
            comment(likes: 9, ageHours: 50),
            comment(likes: 0, ageHours: 0.2),
            comment(likes: 40, ageHours: 300),
        ]
        let order = ranked(comments)
        XCTAssertEqual(Set(order.map(\.id)), Set(comments.map(\.id)))
        XCTAssertEqual(order.count, comments.count)
    }
}
