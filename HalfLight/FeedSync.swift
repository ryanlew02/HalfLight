//
//  FeedSync.swift
//  HalfLight
//
//  The Supabase layer for the social feed. Unlike `DreamSync` (a per-user backup
//  of a local-owned library), the feed is shared across users, so the server is
//  the source of truth here and local SwiftData is a cache kept in step by
//  `DreamStore.reconcileFeed()`. Writes go local-first then push best-effort.
//
//  What's wired through Supabase (see `feed_schema.sql` for the tables):
//    • feed_posts    — a shared dream someone published (author snapshot + counts)
//    • feed_likes    — one row per (user, post); the like-per-view numerator
//    • feed_views    — one row per (user, post); the conversion-rate denominator
//    • feed_comments — comments on a post
//    • follows       — who follows whom
//
//  Engagement counts (like/view/comment) live as columns on `feed_posts`, kept
//  current by DB triggers, so the ranker can read them straight off each row.
//

import Foundation

/// Wire shape of a row in `feed_posts`. snake_case to match Postgres.
struct FeedPostRecord: Codable, Sendable {
    var id: UUID
    var dreamID: UUID
    var authorID: UUID
    var authorUsername: String
    var authorName: String
    var title: String
    var dreamDescription: String
    var createdAt: Date
    var likeCount: Int
    var viewCount: Int
    var commentCount: Int
    var mood: String?
    // Optional so a missing column (older row / migration not yet applied) decodes
    // to nil instead of throwing — a decode failure here would fail the whole feed
    // fetch. Coalesced to [] at the use sites.
    var tags: [String]?
    var aiCategory: String?
    var aiMeaning: String?
    var aiThemes: [String]?

    enum CodingKeys: String, CodingKey {
        case id, title, mood, tags
        case dreamID = "dream_id"
        case authorID = "author_id"
        case authorUsername = "author_username"
        case authorName = "author_name"
        case dreamDescription = "dream_description"
        case createdAt = "created_at"
        case likeCount = "like_count"
        case viewCount = "view_count"
        case commentCount = "comment_count"
        case aiCategory = "ai_category"
        case aiMeaning = "ai_meaning"
        case aiThemes = "ai_themes"
    }
}

/// The columns sent when publishing/editing a post. Deliberately omits the
/// engagement counts so an upsert never overwrites the server's trigger-maintained
/// like/view/comment totals.
struct FeedPostUpsert: Codable, Sendable {
    var id: UUID
    var dreamID: UUID
    var authorID: UUID
    var authorUsername: String
    var authorName: String
    var title: String
    var dreamDescription: String
    var createdAt: Date
    var mood: String?
    var tags: [String]
    var aiCategory: String?
    var aiMeaning: String?
    var aiThemes: [String]

    enum CodingKeys: String, CodingKey {
        case id, title, mood, tags
        case dreamID = "dream_id"
        case authorID = "author_id"
        case authorUsername = "author_username"
        case authorName = "author_name"
        case dreamDescription = "dream_description"
        case createdAt = "created_at"
        case aiCategory = "ai_category"
        case aiMeaning = "ai_meaning"
        case aiThemes = "ai_themes"
    }
}

/// Wire shape of a row in `feed_comments`.
struct FeedCommentRecord: Codable, Sendable {
    var id: UUID
    var postID: UUID
    var authorID: UUID
    var authorUsername: String
    var authorName: String
    var text: String
    var createdAt: Date
    var likeCount: Int = 0

    enum CodingKeys: String, CodingKey {
        case id, text
        case postID = "post_id"
        case authorID = "author_id"
        case authorUsername = "author_username"
        case authorName = "author_name"
        case createdAt = "created_at"
        case likeCount = "like_count"
    }
}

/// Wire shape of a row in `notifications` — a like/comment on the dreamer's post.
struct FeedNotificationRecord: Codable, Sendable {
    var id: UUID
    var type: String
    var actorUsername: String
    var actorName: String
    var postID: UUID?
    var postTitle: String
    var commentText: String?
    var createdAt: Date
    var readAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, type
        case actorUsername = "actor_username"
        case actorName = "actor_name"
        case postID = "post_id"
        case postTitle = "post_title"
        case commentText = "comment_text"
        case createdAt = "created_at"
        case readAt = "read_at"
    }
}

/// Remote feed operations. A `nil` sync (no package / not configured) keeps the
/// feed local-only — exactly today's behavior.
protocol FeedSyncing: Sendable {
    func currentUserID() async -> UUID?

    // Posts
    func publish(_ post: FeedPostUpsert) async throws
    func unpublish(dreamID: UUID) async throws
    func fetchFeed(limit: Int) async throws -> [FeedPostRecord]

    // Engagement
    func likedPostIDs() async throws -> [UUID]
    func setLike(postID: UUID, liked: Bool) async throws
    func recordView(postID: UUID) async throws

    // Comments
    func fetchComments(postID: UUID) async throws -> [FeedCommentRecord]
    func addComment(_ comment: FeedCommentRecord) async throws
    func deleteComment(id: UUID) async throws
    func likedCommentIDs(postID: UUID) async throws -> [UUID]
    func setCommentLike(commentID: UUID, liked: Bool) async throws

    // Follows
    func followedUsernames() async throws -> [String]
    func follow(username: String) async throws
    func unfollow(username: String) async throws

    // Notifications
    func fetchNotifications(limit: Int) async throws -> [FeedNotificationRecord]
    func markAllNotificationsRead() async throws

    // Reports
    func reportPost(postID: UUID, reason: String) async throws
    func reportComment(commentID: UUID, reason: String) async throws
}

#if canImport(Supabase)
import Supabase

final class SupabaseFeedSync: FeedSyncing, @unchecked Sendable {
    private var client: SupabaseClient { SupabaseClientProvider.shared }

    func currentUserID() async -> UUID? {
        (try? await client.auth.session)?.user.id
    }

    // MARK: Posts

    func publish(_ post: FeedPostUpsert) async throws {
        // Omits the count columns, so an edit leaves the server's totals intact.
        try await client.from("feed_posts").upsert(post, onConflict: "id").execute()
    }

    func unpublish(dreamID: UUID) async throws {
        // RLS scopes the delete to the caller's own row.
        try await client.from("feed_posts")
            .delete()
            .eq("dream_id", value: dreamID.uuidString)
            .execute()
    }

    func fetchFeed(limit: Int) async throws -> [FeedPostRecord] {
        try await client.from("feed_posts")
            .select()
            // Drop anything a moderator has hidden via the admin dashboard.
            .eq("hidden", value: false)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value
    }

    // MARK: Engagement

    func likedPostIDs() async throws -> [UUID] {
        guard let uid = await currentUserID() else { return [] }
        let rows: [LikeRow] = try await client.from("feed_likes")
            .select("post_id")
            .eq("user_id", value: uid.uuidString)
            .execute()
            .value
        return rows.map(\.postID)
    }

    func setLike(postID: UUID, liked: Bool) async throws {
        guard let uid = await currentUserID() else { return }
        if liked {
            try await client.from("feed_likes")
                .upsert(LikeRow(userID: uid, postID: postID), onConflict: "user_id,post_id")
                .execute()
        } else {
            try await client.from("feed_likes")
                .delete()
                .eq("user_id", value: uid.uuidString)
                .eq("post_id", value: postID.uuidString)
                .execute()
        }
    }

    func recordView(postID: UUID) async throws {
        guard let uid = await currentUserID() else { return }
        // ignoreDuplicates so a repeat view doesn't error — one impression per user.
        try await client.from("feed_views")
            .upsert(ViewRow(userID: uid, postID: postID), onConflict: "user_id,post_id", ignoreDuplicates: true)
            .execute()
    }

    // MARK: Comments

    func fetchComments(postID: UUID) async throws -> [FeedCommentRecord] {
        try await client.from("feed_comments")
            .select()
            .eq("post_id", value: postID.uuidString)
            // Drop anything a moderator has hidden via the admin dashboard.
            .eq("hidden", value: false)
            .order("created_at", ascending: true)
            .execute()
            .value
    }

    func addComment(_ comment: FeedCommentRecord) async throws {
        try await client.from("feed_comments").insert(comment).execute()
    }

    func deleteComment(id: UUID) async throws {
        try await client.from("feed_comments")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }

    func likedCommentIDs(postID: UUID) async throws -> [UUID] {
        guard let uid = await currentUserID() else { return [] }
        let rows: [CommentLikeRow] = try await client.from("feed_comment_likes")
            .select("comment_id, feed_comments!inner(post_id)")
            .eq("user_id", value: uid.uuidString)
            .eq("feed_comments.post_id", value: postID.uuidString)
            .execute()
            .value
        return rows.map(\.commentID)
    }

    func setCommentLike(commentID: UUID, liked: Bool) async throws {
        guard let uid = await currentUserID() else { return }
        if liked {
            try await client.from("feed_comment_likes")
                .upsert(CommentLikeRow(userID: uid, commentID: commentID), onConflict: "user_id,comment_id")
                .execute()
        } else {
            try await client.from("feed_comment_likes")
                .delete()
                .eq("user_id", value: uid.uuidString)
                .eq("comment_id", value: commentID.uuidString)
                .execute()
        }
    }

    // MARK: Follows

    func followedUsernames() async throws -> [String] {
        guard let uid = await currentUserID() else { return [] }
        let rows: [FollowRow] = try await client.from("follows")
            .select("followee_username")
            .eq("follower_id", value: uid.uuidString)
            .execute()
            .value
        return rows.map(\.followeeUsername)
    }

    func follow(username: String) async throws {
        guard let uid = await currentUserID() else { return }
        try await client.from("follows")
            .upsert(FollowRow(followerID: uid, followeeUsername: username), onConflict: "follower_id,followee_username")
            .execute()
    }

    func unfollow(username: String) async throws {
        guard let uid = await currentUserID() else { return }
        try await client.from("follows")
            .delete()
            .eq("follower_id", value: uid.uuidString)
            .eq("followee_username", value: username)
            .execute()
    }

    // MARK: Notifications

    func fetchNotifications(limit: Int) async throws -> [FeedNotificationRecord] {
        guard let uid = await currentUserID() else { return [] }
        return try await client.from("notifications")
            .select()
            .eq("recipient_id", value: uid.uuidString)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value
    }

    func markAllNotificationsRead() async throws {
        guard let uid = await currentUserID() else { return }
        try await client.from("notifications")
            .update(ReadUpdate(readAt: .now))
            .eq("recipient_id", value: uid.uuidString)
            .is("read_at", value: nil)
            .execute()
    }

    // MARK: Reports

    func reportPost(postID: UUID, reason: String) async throws {
        guard let uid = await currentUserID() else { return }
        // onConflict matches the (reporter, post, comment) unique key so a repeat
        // report updates the reason instead of erroring.
        try await client.from("feed_reports")
            .upsert(ReportRow(reporterID: uid, postID: postID, reason: reason),
                    onConflict: "reporter_id,post_id,comment_id")
            .execute()
    }

    func reportComment(commentID: UUID, reason: String) async throws {
        guard let uid = await currentUserID() else { return }
        try await client.from("feed_reports")
            .upsert(ReportRow(reporterID: uid, commentID: commentID, reason: reason),
                    onConflict: "reporter_id,post_id,comment_id")
            .execute()
    }

    // MARK: Small row shapes

    private struct ReportRow: Codable {
        let reporterID: UUID
        var postID: UUID? = nil
        var commentID: UUID? = nil
        let reason: String
        enum CodingKeys: String, CodingKey {
            case reporterID = "reporter_id"
            case postID = "post_id"
            case commentID = "comment_id"
            case reason
        }
    }

    private struct ReadUpdate: Codable {
        let readAt: Date
        enum CodingKeys: String, CodingKey { case readAt = "read_at" }
    }


    private struct LikeRow: Codable {
        let userID: UUID
        let postID: UUID
        enum CodingKeys: String, CodingKey {
            case userID = "user_id"
            case postID = "post_id"
        }
    }

    private struct ViewRow: Codable {
        let userID: UUID
        let postID: UUID
        enum CodingKeys: String, CodingKey {
            case userID = "user_id"
            case postID = "post_id"
        }
    }

    private struct CommentLikeRow: Codable {
        var userID: UUID? = nil
        let commentID: UUID
        enum CodingKeys: String, CodingKey {
            case userID = "user_id"
            case commentID = "comment_id"
        }
    }

    private struct FollowRow: Codable {
        var followerID: UUID? = nil
        let followeeUsername: String
        enum CodingKeys: String, CodingKey {
            case followerID = "follower_id"
            case followeeUsername = "followee_username"
        }
    }
}
#endif
