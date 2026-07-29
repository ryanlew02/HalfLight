//
//  FeedPost.swift
//  HalfLight
//
//  A dream shared to the social feed. Persisted locally via SwiftData — the same
//  local-first model the rest of the app uses, so a Supabase `feed_posts` sync
//  layer (mirroring `DreamSync`) can hook in later without changing the UI.
//
//  A post is a *snapshot* of the dream at share time: the title and description
//  are copied in, and the author's username / name / photo are captured so the
//  card can render even before a real multi-user backend exists.
//

import Foundation
import SwiftData

@Model
final class FeedPost {
    /// Stable identifier for the post (also the future remote row id).
    @Attribute(.unique) var id: UUID
    /// The source dream this post was shared from, so a dream is only posted once.
    var dreamID: UUID

    // MARK: Author (snapshot — until profiles are fetched from the server)

    /// The author's handle, rendered with a leading "@".
    var authorUsername: String
    /// The author's display name, used for the avatar initials fallback.
    var authorName: String
    /// The author's cropped profile photo (JPEG), or `nil` to fall back to initials.
    @Attribute(.externalStorage) var authorPhoto: Data?

    // MARK: Content

    var title: String
    /// The dream's description (its `entry`), copied at share time.
    var dreamDescription: String
    var createdAt: Date

    // MARK: Mood + tags (snapshot, so other dreamers see them on the card)

    /// The dream's mood, stored as its raw value and rebuilt into `Dream.Mood`
    /// for the feeling label, the tag tint, and the corner mood orb.
    var mood: String?
    /// The dreamer's own tags, copied at share time.
    var tags: [String] = []

    // MARK: AI analysis (snapshot of the dream's interpretation)

    /// The AI category / meaning / themes, copied from the source dream so other
    /// dreamers — who don't have that dream locally — still see the analysis on
    /// the card. `nil` / empty until the dream has been analyzed.
    var aiCategory: String?
    var aiMeaning: String?
    var aiThemes: [String] = []

    // MARK: Engagement (local for now; a real backend will own the counts)

    var likeCount: Int
    /// Whether the current dreamer has liked this post.
    var isLiked: Bool
    var commentCount: Int
    /// How many times this post has been shown in a feed (impressions). With
    /// `likeCount` this gives the like-per-view conversion rate the ranker treats
    /// as "virality" — see `FeedRanker`.
    var viewCount: Int = 0

    /// True for a post cached only because the dreamer opened it from search.
    /// Liking and commenting need a local `FeedPost`, but a searched post may be
    /// far older than the feed window — so it's kept out of the feed's query and
    /// cleared the moment `reconcileFeed` sees it come back from the server.
    var isSearchResult: Bool = false

    init(
        id: UUID = UUID(),
        dreamID: UUID,
        authorUsername: String,
        authorName: String,
        authorPhoto: Data? = nil,
        title: String,
        dreamDescription: String,
        createdAt: Date = .now,
        likeCount: Int = 0,
        isLiked: Bool = false,
        commentCount: Int = 0,
        viewCount: Int = 0,
        mood: String? = nil,
        tags: [String] = [],
        aiCategory: String? = nil,
        aiMeaning: String? = nil,
        aiThemes: [String] = [],
        isSearchResult: Bool = false
    ) {
        self.id = id
        self.dreamID = dreamID
        self.authorUsername = authorUsername
        self.authorName = authorName
        self.authorPhoto = authorPhoto
        self.title = title
        self.dreamDescription = dreamDescription
        self.createdAt = createdAt
        self.likeCount = likeCount
        self.isLiked = isLiked
        self.commentCount = commentCount
        self.viewCount = viewCount
        self.mood = mood
        self.tags = tags
        self.aiCategory = aiCategory
        self.aiMeaning = aiMeaning
        self.aiThemes = aiThemes
        self.isSearchResult = isSearchResult
    }
}
