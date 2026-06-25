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

    /// Where Supabase should send the user after they tap the password-reset
    /// link in their email. Leave `nil` to fall back to the project's Site URL
    /// (which defaults to http://localhost:3000 — hence reset links pointing at
    /// localhost).
    ///
    /// To send users back into the app instead:
    ///   1. Register a URL scheme in Xcode (Target → Info → URL Types), e.g.
    ///      `halflight`.
    ///   2. In the Supabase dashboard → Authentication → URL Configuration, add
    ///      the same URL (e.g. `halflight://reset-password`) to **Redirect
    ///      URLs**, and set a real **Site URL** (no longer localhost).
    ///   3. Set this to `URL(string: "halflight://reset-password")` and handle
    ///      the incoming link to present a "set new password" screen.
    ///
    /// NOTE: a `redirectTo` that isn't in the dashboard allowlist is rejected, so
    /// only set this once steps 1–2 are done.
    ///
    /// Wired up: the `halflight` URL scheme is registered (HalfLight/Info.plist)
    /// and `halflight://reset-password` must be listed under Supabase →
    /// Authentication → URL Configuration → Redirect URLs. The incoming link is
    /// handled in `HalfLightApp` → `AuthService.handlePasswordResetLink`.
    static let passwordResetRedirect: URL? = URL(string: "halflight://reset-password")

    /// True once real values have been filled in (used to surface a clear
    /// message instead of failing cryptically while still on placeholders).
    static var isConfigured: Bool {
        !urlString.contains("YOUR-PROJECT") && !anonKey.contains("YOUR-ANON")
    }
}
