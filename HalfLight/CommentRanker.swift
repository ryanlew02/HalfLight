//
//  CommentRanker.swift
//  HalfLight
//
//  Orders the comments on a feed post. Each comment is scored on three signals
//  and sorted by the total, so the list leads with the best-loved comments while
//  still mixing in ones that are catching on or were just posted:
//
//    1. Top      — how many likes it has (log-scaled, so a runaway favorite
//                  doesn't bury everything else forever).
//    2. Trending — likes relative to how long it's been up (a like-velocity), so
//                  a fresh comment gathering likes outranks an old one that
//                  slowly accumulated the same total.
//    3. Fresh    — just posted, so brand-new comments get a look even before
//                  they've earned any likes.
//
//  A weighted sum (rather than sorting by one field) is what interleaves the
//  three: a hugely-liked comment still tops the list, but trending and fresh
//  comments rise between the all-time favorites instead of being stranded at the
//  bottom in pure-recency or pure-likes order.
//
//  Pure function of its inputs (no I/O) — cheap to call and easy to test/tune,
//  mirroring `FeedRanker`.
//

import Foundation

enum CommentRanker {

    // MARK: Tunables

    /// Relative importance of each signal — this is what sets the precedence.
    static let topWeight = 1.0
    static let trendingWeight = 0.7
    static let freshnessWeight = 0.3

    /// Hours added to the denominator of the like-velocity (Bayesian smoothing),
    /// so a comment that's one minute old with a single like doesn't read as
    /// infinitely trending.
    static let trendingSmoothingHours = 2.0
    /// Hours after which a comment's freshness decays to ~37% (one time constant).
    static let freshnessHalfLifeHours = 6.0

    // MARK: Ranking

    /// Returns `comments` ordered best-first for the comments sheet.
    static func rank(_ comments: [Comment], now: Date = .now) -> [Comment] {
        guard comments.count > 1 else { return comments }

        // Normalize the two unbounded signals across the batch so each lands on a
        // [0,1] scale and the weights stay meaningful regardless of absolute likes.
        let maxTop = max(comments.map { topSignal($0) }.max() ?? 0, 0.0001)
        let maxTrending = max(comments.map { trendingSignal($0, now: now) }.max() ?? 0, 0.0001)

        let scored: [(comment: Comment, score: Double)] = comments.map { comment in
            let top = topSignal(comment) / maxTop
            let trending = trendingSignal(comment, now: now) / maxTrending
            let fresh = freshnessSignal(comment, now: now)
            let score = topWeight * top
                + trendingWeight * trending
                + freshnessWeight * fresh
            return (comment, score)
        }

        // Highest score first; newest breaks ties so the order is stable.
        return scored
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.comment.createdAt > rhs.comment.createdAt
                }
                return lhs.score > rhs.score
            }
            .map(\.comment)
    }

    // MARK: Signals (exposed for tests/tuning)

    /// Top: log-scaled like count, so each extra like matters less than the last.
    static func topSignal(_ comment: Comment) -> Double {
        log1p(Double(max(0, comment.likeCount)))
    }

    /// Trending: likes per hour since posting (smoothed), a like-velocity that
    /// rewards comments gathering likes quickly over ones that aged into them.
    static func trendingSignal(_ comment: Comment, now: Date = .now) -> Double {
        let ageHours = max(0, now.timeIntervalSince(comment.createdAt) / 3600)
        return Double(max(0, comment.likeCount)) / (ageHours + trendingSmoothingHours)
    }

    /// Fresh: pure recency decay, so a just-posted comment surfaces even with no
    /// likes yet.
    static func freshnessSignal(_ comment: Comment, now: Date = .now) -> Double {
        let ageHours = max(0, now.timeIntervalSince(comment.createdAt) / 3600)
        return exp(-ageHours / freshnessHalfLifeHours)
    }
}
