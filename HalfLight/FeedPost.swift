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

    // MARK: Engagement (local for now; a real backend will own the counts)

    var likeCount: Int
    /// Whether the current dreamer has liked this post.
    var isLiked: Bool
    var commentCount: Int
    /// How many times this post has been shown in a feed (impressions). With
    /// `likeCount` this gives the like-per-view conversion rate the ranker treats
    /// as "virality" — see `FeedRanker`.
    var viewCount: Int = 0

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
        viewCount: Int = 0
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
    }
}
