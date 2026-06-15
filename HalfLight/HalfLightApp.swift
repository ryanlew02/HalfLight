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
    @State private var store: DreamStore?

    var body: some View {
        Group {
            if let store {
                ContentView()
                    .environment(store)
            } else {
                Color.clear
            }
        }
        .task {
            guard store == nil else { return }
            let store = DreamStore(context: modelContext)
            store.seedSampleDataIfNeeded()
            self.store = store
        }
    }
}
