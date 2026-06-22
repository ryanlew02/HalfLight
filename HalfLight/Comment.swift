//
//  Comment.swift
//  HalfLight
//
//  A comment on a feed post, stored locally via SwiftData. Like `FeedPost`, the
//  author's handle / name / photo are snapshotted so the row renders without a
//  server round-trip; a Supabase `comments` table can sync these later.
//

import Foundation
import SwiftData

@Model
final class Comment {
    @Attribute(.unique) var id: UUID
    /// The post this comment belongs to.
    var postID: UUID

    // MARK: Author (snapshot)

    var authorUsername: String
    var authorName: String
    @Attribute(.externalStorage) var authorPhoto: Data?

    // MARK: Content

    var text: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        postID: UUID,
        authorUsername: String,
        authorName: String,
        authorPhoto: Data? = nil,
        text: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.postID = postID
        self.authorUsername = authorUsername
        self.authorName = authorName
        self.authorPhoto = authorPhoto
        self.text = text
        self.createdAt = createdAt
    }
}
