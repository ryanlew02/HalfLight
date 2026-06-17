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
    @State private var tabBarHeight: CGFloat = 0

    var body: some View {
        ZStack {
            currentScreen
                .id(selection)
                .transition(.opacity)
        }
            .foregroundStyle(Color.dreamText)
            .environment(\.tabBarHeight, tabBarHeight)
            .safeAreaInset(edge: .bottom) {
                CustomTabBar(selection: $selection) {
                    isAddingDream = true
                }
                .measuresTabBarHeight()
            }
            .onPreferenceChange(TabBarHeightPreferenceKey.self) { tabBarHeight = $0 }
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
        .environment(AuthService())
}

#Preview("Dark") {
    MainTabView()
        .modelContainer(PreviewData.container)
        .environment(PreviewData.store)
        .environment(AuthService())
        .preferredColorScheme(.dark)
}
