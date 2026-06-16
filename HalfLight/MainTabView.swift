//
//  MainTabView.swift
//  HalfLight
//
//  Root shell: hosts the selected screen and the bottom tab bar, and owns the
//  global "add dream" sheet triggered by the center "+".
//

import SwiftUI
import SwiftData

struct MainTabView: View {
    @Environment(DreamStore.self) private var store
    @State private var selection: AppTab = .home
    @State private var isAddingDream = false

    var body: some View {
        currentScreen
            .foregroundStyle(Color.dreamText)
            .safeAreaInset(edge: .bottom) {
                CustomTabBar(selection: $selection) {
                    isAddingDream = true
                }
            }
            .fullScreenCover(isPresented: $isAddingDream) {
                AddDreamView { draft in
                    store.add(draft)
                }
            }
    }

    @ViewBuilder
    private var currentScreen: some View {
        switch selection {
        case .home: HomeView()
        case .journal: DreamJournalView()
        case .lucid: LucidDreamView()
        case .stats: StatsView()
        }
    }
}

#Preview("Light") {
    MainTabView()
        .modelContainer(PreviewData.container)
        .environment(PreviewData.store)
}

#Preview("Dark") {
    MainTabView()
        .modelContainer(PreviewData.container)
        .environment(PreviewData.store)
        .preferredColorScheme(.dark)
}
