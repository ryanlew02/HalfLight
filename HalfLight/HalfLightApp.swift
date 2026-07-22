//
//  HalfLightApp.swift
//  HalfLight
//
//  Created by Ryan Lewandowski on 6/13/26.
//

import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
import UserNotifications

/// Receives the APNs device token and forwards it to `PushService`, and presents
/// pushes while the app is foregrounded.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        PushService.shared.updateToken(deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Best-effort: no token this launch (e.g. simulator, no entitlement yet).
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }
}
#endif

@main
struct HalfLightApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    init() {
        // Register any bundled custom faces (Instrument Serif / Space Grotesk /
        // JetBrains Mono). No-op until the TTFs are added to the target, at which
        // point the type system upgrades from its system-font fallbacks.
        DreamFonts.registerBundled()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [Dream.self, DeletedDream.self, FeedPost.self, Follow.self, Comment.self, AppNotification.self])
    }
}

/// Builds the `DreamStore` from the SwiftUI-owned model context and injects it.
private struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("appTheme") private var theme: AppTheme = .system
    /// One-time first-launch onboarding gate. Set once the dreamer finishes the
    /// intro — whether they sign up or choose to continue as a guest.
    @AppStorage("didCompleteOnboarding") private var didCompleteOnboarding = false
    @State private var store: DreamStore?
    @State private var auth = AuthService()
    @State private var subscriptions = SubscriptionManager()
    @State private var language = LanguageManager.shared
    /// Drives the sign-in "merge this device's data?" prompt: the count of guest
    /// dreams and whether there's local Lucid Path progress shape its wording.
    @State private var showMergePrompt = false
    @State private var pendingMergeDreamCount = 0
    @State private var pendingMergeHasLucid = false

    var body: some View {
        Group {
            if let store {
                Group {
                    // Signed in via Apple (or an older account from before usernames)
                    // but no handle yet: block the app behind a one-time setup gate.
                    if auth.needsProfileSetup {
                        UsernameSetupView()
                    } else if !didCompleteOnboarding && !auth.isSignedIn {
                        // First launch as a guest: show the intro tour. A returning
                        // signed-in dreamer (restored session) skips straight past it.
                        OnboardingView(onContinueAsGuest: { didCompleteOnboarding = true })
                    } else {
                        MainTabView()
                    }
                }
                .environment(store)
                .environment(auth)
                .environment(subscriptions)
                .environment(language)
                .tint(.dreamPrimary)
                .preferredColorScheme(theme.colorScheme)
                // Drive number/date formatting and text direction from the
                // chosen language, and rebuild the whole tree on change so every
                // `Text` re-reads the now-repointed localized bundle.
                .environment(\.locale, language.current.locale)
                .environment(\.layoutDirection, language.current.isRTL ? .rightToLeft : .leftToRight)
                .id(language.current)
            } else {
                // Before the store is ready, show the launch backdrop so there's no
                // flash before MainTabView's dreamy loading screen takes over.
                NightSkyBackground()
            }
        }
        // Tap anywhere outside a text field to dismiss the keyboard, app-wide.
        .dismissKeyboardOnTapOutside()
        .task {
            if store == nil {
                store = makeStore()
                // Ensure dreams already marked public have a feed post (and drop
                // any left behind by now-private dreams), then bring each post's
                // author snapshot up to date with the current profile.
                store?.backfillFeedPosts()
                store?.refreshFeedAuthors()
                // One-time: re-sync public/lucid flags that older builds never
                // uploaded, so dreams made public on one device aren't private here.
                store?.republishVisibilityIfNeeded()
            }
            // Load products and begin observing entitlement changes for the
            // AI-feature paywall.
            await subscriptions.start()
            // Restoring may flip auth to signed-in, which triggers a reconcile
            // via onChange below.
            await auth.restore()
        }
        .onChange(of: auth.status) { previous, status in
            if status == .signedIn {
                // Signing up from onboarding (or restoring a session) means the
                // intro is done — never show it again for this account.
                didCompleteOnboarding = true
                store?.reconcileFeed()
                store?.reconcileNotifications()
                // Self-heal the server entitlement: if this account is subscribed
                // on the device but has no subscriptions row yet, push it now so
                // the AI gate sees it.
                Task { await subscriptions.syncIfEntitled() }
                // Register for APNs and upload this device's token so the
                // push-notify function can reach the dreamer.
                PushService.shared.start()
                switch auth.lastEntry {
                case .signedIn:
                    // Logging into an existing account: if there's guest data on this
                    // device (dreams or Lucid Path progress), ask whether to merge it
                    // before pulling the account's. With none, just reconcile.
                    let dreamCount = store?.unownedLocalDreamCount() ?? 0
                    let hasLucid = !LucidProgress.completedIDs().isEmpty
                    if dreamCount > 0 || hasLucid {
                        pendingMergeDreamCount = dreamCount
                        pendingMergeHasLucid = hasLucid
                        showMergePrompt = true
                    } else {
                        store?.reconcileWithRemote(claimLocalDreams: false)
                        Task {
                            await auth.syncLucidProgress()
                            if await auth.syncProgressState() { store?.refreshDayLogs() }
                        }
                    }
                case .signedUp, .none:
                    // A new account (or a launch session-restore): adopt any
                    // on-device dreams and Lucid Path progress into the account.
                    store?.reconcileWithRemote(claimLocalDreams: true)
                    Task {
                        await auth.syncLucidProgress()
                        if await auth.syncProgressState() { store?.refreshDayLogs() }
                    }
                }
            } else if status == .signedOut, previous == .signedIn {
                // A real sign-out (not a guest simply launching the app, which goes
                // .unknown → .signedOut): clear the account's local dreams and Lucid
                // Path progress so they don't linger for the next person. Both are
                // backed up on the server and rehydrate on the next sign-in.
                store?.wipeLocalData()
                auth.clearLocalLucidProgress()
                // Reset the rest of the local progression — quests, achievements and
                // level celebrations — so the next account (or guest) starts fresh
                // rather than inheriting this account's progress. XP and quest/
                // achievement state are derived locally, so they rebuild from the
                // account's own dreams on the next sign-in.
                QuestRewards.reset()
                AchievementTracker.reset()
                UserDefaults.standard.removeObject(forKey: "celebratedLevel")
            }
        }
        // Logging into an existing account with guest data on the device: let the
        // dreamer keep it (merge into the account) or discard it.
        .alert("Merge this device's data?", isPresented: $showMergePrompt) {
            Button("Merge") {
                store?.reconcileWithRemote(claimLocalDreams: true)
                Task {
                    await auth.syncLucidProgress()
                    if await auth.syncProgressState() { store?.refreshDayLogs() }
                }
                showMergePrompt = false
            }
            Button("Don't Merge", role: .destructive) {
                store?.reconcileWithRemote(claimLocalDreams: false)
                Task {
                    await auth.discardLocalLucidProgress()
                    if await auth.discardLocalProgressState() { store?.refreshDayLogs() }
                }
                showMergePrompt = false
            }
        } message: {
            Text(mergePromptMessage)
        }
        // Auth email links reopen the app here. Each handler ignores URLs that
        // aren't its own: reset-password redeems a recovery session and presents
        // the "set a new password" screen; confirm-email completes a sign-up.
        .onOpenURL { url in
            Task {
                await auth.handlePasswordResetLink(url)
                await auth.handleEmailConfirmLink(url)
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { auth.isPresentingPasswordReset },
            set: { auth.isPresentingPasswordReset = $0 }
        )) {
            ResetPasswordView()
                .environment(auth)
                .environment(language)
                .tint(.dreamPrimary)
                .preferredColorScheme(theme.colorScheme)
                .environment(\.locale, language.current.locale)
                .environment(\.layoutDirection, language.current.isRTL ? .rightToLeft : .leftToRight)
        }
        .alert(
            "Couldn't open reset link",
            isPresented: Binding(
                get: { auth.passwordResetError != nil },
                set: { if !$0 { auth.passwordResetError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { auth.passwordResetError = nil }
        } message: {
            Text(auth.passwordResetError ?? "")
        }
        .alert(
            "Couldn't confirm your email",
            isPresented: Binding(
                get: { auth.emailConfirmError != nil },
                set: { if !$0 { auth.emailConfirmError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { auth.emailConfirmError = nil }
        } message: {
            Text(auth.emailConfirmError ?? "")
        }
    }

    /// The merge prompt's body, naming whatever guest data is on the device.
    private var mergePromptMessage: String {
        let d = pendingMergeDreamCount
        let dreamPhrase = d == 1 ? "1 dream" : "\(d) dreams"
        let item: String
        if d > 0 && pendingMergeHasLucid {
            item = "\(dreamPhrase) and your Lucid Path progress"
        } else if pendingMergeHasLucid {
            item = "your Lucid Path progress"
        } else {
            item = dreamPhrase
        }
        return "You have \(item) saved on this device that isn't part of your account. "
            + "Merge it into your account? If you don't, it will be permanently deleted from this device."
    }

    /// Builds the store with remote backends (dream backup + social feed) when
    /// Supabase is available.
    private func makeStore() -> DreamStore {
        #if canImport(Supabase)
        DreamStore(context: modelContext, sync: SupabaseDreamSync(), feedSync: SupabaseFeedSync())
        #else
        DreamStore(context: modelContext)
        #endif
    }
}
