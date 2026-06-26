//
//  AppNotification.swift
//  HalfLight
//
//  A like/comment notification on the dreamer's own post, cached locally via
//  SwiftData and kept in step with the server by `DreamStore.reconcileNotifications()`.
//  Like `FeedPost` / `Comment`, the actor's handle / name and the post title are
//  snapshotted so a row renders without a join. The server owns these rows (written
//  by triggers — see the `notifications` migration); the client only reads and marks
//  them read.
//

import Foundation
import SwiftData

@Model
final class AppNotification {
    @Attribute(.unique) var id: UUID
    /// "like" or "comment".
    var type: String

    // MARK: Actor (snapshot)

    var actorUsername: String
    var actorName: String

    // MARK: Context

    /// The post the activity is about, used to open its thread.
    var postID: UUID?
    var postTitle: String
    /// The comment body, for comment notifications.
    var commentText: String?

    var createdAt: Date
    /// Mirrors the server's `read_at` (nil ⇒ unread); kept as a bool locally.
    var isRead: Bool

    /// Strongly-typed view over `type`.
    var kind: Kind { Kind(rawValue: type) ?? .like }

    enum Kind: String {
        case like, comment
    }

    init(
        id: UUID,
        type: String,
        actorUsername: String,
        actorName: String,
        postID: UUID?,
        postTitle: String,
        commentText: String?,
        createdAt: Date,
        isRead: Bool
    ) {
        self.id = id
        self.type = type
        self.actorUsername = actorUsername
        self.actorName = actorName
        self.postID = postID
        self.postTitle = postTitle
        self.commentText = commentText
        self.createdAt = createdAt
        self.isRead = isRead
    }
}
