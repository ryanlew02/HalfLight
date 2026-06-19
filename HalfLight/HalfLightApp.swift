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
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: Dream.self)
    }
}

/// Builds the `DreamStore` from the SwiftUI-owned model context and injects it.
private struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("appTheme") private var theme: AppTheme = .system
    @State private var store: DreamStore?
    @State private var auth = AuthService()

    var body: some View {
        Group {
            if let store {
                MainTabView()
                    .environment(store)
                    .environment(auth)
                    .tint(.dreamPrimary)
                    .preferredColorScheme(theme.colorScheme)
            } else {
                Color.clear
            }
        }
        .task {
            if store == nil {
                store = makeStore()
            }
            // Restoring may flip auth to signed-in, which triggers a reconcile
            // via onChange below.
            await auth.restore()
        }
        .onChange(of: auth.status) { _, status in
            if status == .signedIn {
                store?.reconcileWithRemote()
            }
        }
    }

    /// Builds the store with a remote sync backend when Supabase is available.
    private func makeStore() -> DreamStore {
        #if canImport(Supabase)
        DreamStore(context: modelContext, sync: SupabaseDreamSync())
        #else
        DreamStore(context: modelContext)
        #endif
    }
}
