//
//  Follow.swift
//  HalfLight
//
//  A dreamer this user follows, stored locally via SwiftData. One row per followed
//  handle. Local-first like the rest of the app — a Supabase `follows` table can
//  sync these later without changing the UI.
//

import Foundation
import SwiftData

@Model
final class Follow {
    /// The followed dreamer's handle (without the leading "@"). Unique so a person
    /// can only be followed once.
    @Attribute(.unique) var username: String
    var followedAt: Date

    init(username: String, followedAt: Date = .now) {
        self.username = username
        self.followedAt = followedAt
    }
}
