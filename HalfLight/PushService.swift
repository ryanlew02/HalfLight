//
//  PushService.swift
//  HalfLight
//
//  Registers the device for APNs and uploads its token to `device_tokens`, so the
//  `push-notify` Edge Function can deliver like/comment pushes. The token arrives
//  in the app delegate (outside the SwiftUI environment), so this is a singleton —
//  mirroring `ReminderScheduler` — that holds the latest token and uploads it once
//  a signed-in session exists.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif
import UserNotifications

@MainActor
final class PushService {
    static let shared = PushService()
    private init() {}

    /// The most recent APNs token (hex), kept so we can (re)upload after sign-in.
    private var token: String?

    /// Ensure notification permission, then ask the system for an APNs token. The
    /// token is delivered to `AppDelegate` and forwarded to `updateToken`. Safe to
    /// call repeatedly (e.g. on every sign-in).
    func start() {
        #if canImport(UIKit)
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            var granted = settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
            if settings.authorizationStatus == .notDetermined {
                granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            }
            guard granted else { return }
            UIApplication.shared.registerForRemoteNotifications()
            // If we already have a token from a prior launch, push it now that
            // we're (re)started — covers the sign-in-after-launch case.
            await upload()
        }
        #endif
    }

    /// Called from the app delegate when APNs hands us a device token.
    func updateToken(_ data: Data) {
        token = data.map { String(format: "%02x", $0) }.joined()
        Task { await upload() }
    }

    private func upload() async {
        guard let token else { return }
        await uploadToken(token)
    }

    #if canImport(Supabase)
    private func uploadToken(_ token: String) async {
        guard let uid = await SessionInfo.currentUserID() else { return }
        struct Row: Encodable {
            let token: String
            let user_id: String
            let platform: String
        }
        try? await SupabaseClientProvider.shared
            .from("device_tokens")
            .upsert(Row(token: token, user_id: uid.uuidString, platform: "ios"), onConflict: "token")
            .execute()
    }
    #else
    private func uploadToken(_ token: String) async {}
    #endif
}

#if canImport(Supabase)
import Supabase

/// Small helper to read the current user id without the SwiftUI environment.
private enum SessionInfo {
    static func currentUserID() async -> UUID? {
        (try? await SupabaseClientProvider.shared.auth.session)?.user.id
    }
}
#endif
