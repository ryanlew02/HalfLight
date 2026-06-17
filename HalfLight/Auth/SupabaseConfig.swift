//
//  SupabaseConfig.swift
//  HalfLight
//
//  Connection details for the Supabase project. Fill these in from your
//  Supabase dashboard → Project Settings → API. The anon/public key is safe to
//  ship in a client app; never put the service_role key here.
//

import Foundation

enum SupabaseConfig {
    /// e.g. "https://abcdefghijklm.supabase.co"
    static let urlString = "https://kbklwrvhocyibesvsqqa.supabase.co"
    /// The "anon" public API key.
    static let anonKey = "sb_publishable_gSd0WUQqfONlfOsjuPB27w_XTBgYYCQ"

    static var url: URL {
        guard let url = URL(string: urlString) else {
            preconditionFailure("Invalid SupabaseConfig.urlString")
        }
        return url
    }

    /// True once real values have been filled in (used to surface a clear
    /// message instead of failing cryptically while still on placeholders).
    static var isConfigured: Bool {
        !urlString.contains("YOUR-PROJECT") && !anonKey.contains("YOUR-ANON")
    }
}
