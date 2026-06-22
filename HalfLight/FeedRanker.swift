//
//  FeedRanker.swift
//  HalfLight
//
//  Orders the feed. Each post is scored on four signals and sorted by the total.
//  The weights encode the requested precedence:
//
//    1. Viral         — like-per-view conversion rate (how often people who see
//                       the dream like it).
//    2. Interest      — overlap with themes you've liked, amplified by that same
//                       conversion rate so the best-loved relevant dreams reach you.
//    3. Following     — the author is someone you follow.
//    4. Fresh & quiet — just posted and barely seen yet.
//
//  Conversion rate is the heart of it: a dream that converts views into likes is
//  shown to more people (a higher viral score), and converts harder within the
//  themes you care about. It's smoothed so a post can't look viral off one like
//  on one view, then normalized across the batch so the weights stay meaningful.
//
//  Pure function of its inputs (no I/O) — cheap to call and easy to test/tune.
//

import Foundation

enum FeedRanker {

    // MARK: Tunables

    /// Relative importance of each signal — this is what enforces the precedence.
    static let viralWeight = 1.0
    static let interestWeight = 0.6
    static let followingWeight = 0.35
    static let freshnessWeight = 0.15

    /// Pseudo-views added to the denominator of the conversion rate (Bayesian
    /// smoothing toward 0), so a 1-like / 1-view post isn't treated as 100% viral.
    static let conversionSmoothing = 8.0
    /// Hours after which a post's freshness decays to ~37% (one time constant).
    static let freshnessHalfLifeHours = 6.0

    // MARK: Ranking

    /// Returns `posts` ordered best-first for this dreamer.
    static func rank(
        posts: [FeedPost],
        dreamsByID: [UUID: Dream],
        followedUsernames: Set<String>,
        now: Date = .now
    ) -> [FeedPost] {
        let affinity = likedThemeAffinity(in: posts, dreamsByID: dreamsByID)

        // Conversion rates for the batch, normalized so the top converter is 1.0 —
        // keeps "viral" on the same [0,1] scale as the other signals regardless of
        // how high real conversion rates run.
        let conversions = Dictionary(uniqueKeysWithValues: posts.map { ($0.id, conversionRate($0)) })
        let maxConversion = max(conversions.values.max() ?? 0, 0.0001)

        let scored: [(post: FeedPost, score: Double)] = posts.map { post in
            let conversion = (conversions[post.id] ?? 0) / maxConversion
            let postScore = score(
                post,
                dreamsByID: dreamsByID,
                affinity: affinity,
                followedUsernames: followedUsernames,
                normalizedConversion: conversion,
                now: now
            )
            return (post, postScore)
        }

        // Highest score first; newest breaks ties so the order is stable.
        return scored
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.post.createdAt > rhs.post.createdAt
                }
                return lhs.score > rhs.score
            }
            .map(\.post)
    }

    /// Smoothed like-per-view conversion rate for a post.
    static func conversionRate(_ post: FeedPost) -> Double {
        Double(max(0, post.likeCount)) / (Double(max(0, post.viewCount)) + conversionSmoothing)
    }

    /// The composite score for one post. `normalizedConversion` is its conversion
    /// rate scaled to [0,1] across the batch. Exposed for tests/tuning.
    static func score(
        _ post: FeedPost,
        dreamsByID: [UUID: Dream],
        affinity: [String: Double],
        followedUsernames: Set<String>,
        normalizedConversion: Double,
        now: Date = .now
    ) -> Double {
        // 1. Viral — purely how well the dream converts views into likes.
        let viral = normalizedConversion

        // 2. Interest — does this match themes you like, and how hard does it
        //    convert? Relevant + high-converting dreams surface to more people.
        let interestRaw = themes(for: post, dreamsByID: dreamsByID)
            .reduce(0.0) { $0 + (affinity[$1] ?? 0) }
        let interestMatch = interestRaw / (interestRaw + 1)
        let interest = interestMatch * normalizedConversion

        // 3. Following — a flat boost when you follow the author.
        let following = followedUsernames.contains(post.authorUsername.lowercased()) ? 1.0 : 0.0

        // 4. Fresh & quiet — recent *and* barely seen yet (few impressions).
        let ageHours = max(0, now.timeIntervalSince(post.createdAt) / 3600)
        let recency = exp(-ageHours / freshnessHalfLifeHours)
        let lowAttention = 1.0 / (1.0 + Double(max(0, post.viewCount)))
        let freshness = recency * lowAttention

        return viralWeight * viral
            + interestWeight * interest
            + followingWeight * following
            + freshnessWeight * freshness
    }

    // MARK: Interest model

    /// How strongly the dreamer leans toward each theme, learned from the posts
    /// they've liked: every theme on a liked dream gains a point.
    static func likedThemeAffinity(in posts: [FeedPost], dreamsByID: [UUID: Dream]) -> [String: Double] {
        var counts: [String: Double] = [:]
        for post in posts where post.isLiked {
            for theme in themes(for: post, dreamsByID: dreamsByID) {
                counts[theme, default: 0] += 1
            }
        }
        return counts
    }

    /// A post's themes, lowercased: AI themes once the dream is analyzed, otherwise
    /// the tags the dreamer entered. Empty when the source dream isn't local.
    private static func themes(for post: FeedPost, dreamsByID: [UUID: Dream]) -> [String] {
        guard let dream = dreamsByID[post.dreamID] else { return [] }
        let analyzed = dream.aiCategory != nil && dream.aiMeaning != nil
        let source = (analyzed && !dream.aiThemes.isEmpty) ? dream.aiThemes : dream.tags
        return source.map { $0.lowercased() }
    }
}
