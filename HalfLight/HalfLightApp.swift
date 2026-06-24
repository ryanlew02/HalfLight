//
//  HalfLightApp.swift
//  HalfLight
//
//  Created by Ryan Lewandowski on 6/13/26.
//

import SwiftUI
import SwiftData

@main
struct HalfLightApp: App {
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
        .modelContainer(for: [Dream.self, DeletedDream.self, FeedPost.self, Follow.self, Comment.self])
    }
}

/// Builds the `DreamStore` from the SwiftUI-owned model context and injects it.
private struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("appTheme") private var theme: AppTheme = .system
    @State private var store: DreamStore?
    @State private var auth = AuthService()
    @State private var subscriptions = SubscriptionManager()
    @State private var language = LanguageManager.shared

    var body: some View {
        Group {
            if let store {
                Group {
                    // Signed in via Apple (or an older account from before usernames)
                    // but no handle yet: block the app behind a one-time setup gate.
                    if auth.needsProfileSetup {
                        UsernameSetupView()
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
                Color.clear
            }
        }
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
        .onChange(of: auth.status) { _, status in
            if status == .signedIn {
                store?.reconcileWithRemote()
                store?.reconcileFeed()
            }
        }
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
