//
//  DreamSync.swift
//  HalfLight
//
//  Mirrors local dream changes to Supabase (per-user, RLS-protected) and pulls
//  remote dreams when signing in. Local SwiftData remains the source of truth;
//  the remote is a backup kept in step while signed in.
//

import Foundation

/// A transferable, Sendable snapshot of a dream — the wire shape of a row in the
/// Supabase `dreams` table. Column names are snake_case to match Postgres.
struct DreamRecord: Codable, Sendable {
    var id: UUID
    var userID: UUID
    var title: String
    var entry: String
    var date: Date
    var mood: String
    var tags: [String]
    var aiCategory: String?
    var aiMeaning: String?
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, entry, date, mood, tags
        case userID = "user_id"
        case aiCategory = "ai_category"
        case aiMeaning = "ai_meaning"
        case updatedAt = "updated_at"
    }
}

/// Remote backup operations. A `nil` sync (no package / not configured) means the
/// app simply stays local-only.
protocol DreamSyncing: Sendable {
    /// The signed-in user's id, or `nil` when signed out.
    func currentUserID() async -> UUID?
    /// Insert or update one dream remotely.
    func upsert(_ record: DreamRecord) async throws
    /// Delete one dream remotely by id (RLS scopes it to the caller's rows).
    func delete(id: UUID) async throws
    /// Fetch all of a user's dreams.
    func fetchAll(for userID: UUID) async throws -> [DreamRecord]
}

#if canImport(Supabase)
import Supabase

/// One shared client so the auth session and the dream sync use the same JWT.
enum SupabaseClientProvider {
    static let shared = SupabaseClient(
        supabaseURL: SupabaseConfig.url,
        supabaseKey: SupabaseConfig.anonKey
    )
}

final class SupabaseDreamSync: DreamSyncing, @unchecked Sendable {
    private var client: SupabaseClient { SupabaseClientProvider.shared }

    func currentUserID() async -> UUID? {
        (try? await client.auth.session)?.user.id
    }

    func upsert(_ record: DreamRecord) async throws {
        try await client.from("dreams").upsert(record).execute()
    }

    func delete(id: UUID) async throws {
        try await client.from("dreams").delete().eq("id", value: id.uuidString).execute()
    }

    func fetchAll(for userID: UUID) async throws -> [DreamRecord] {
        try await client.from("dreams")
            .select()
            .eq("user_id", value: userID.uuidString)
            .execute()
            .value
    }
}
#endif
