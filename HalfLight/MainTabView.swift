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
    @State private var selection: AppTab = .home
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
                CustomTabBar(selection: $selection)
                    .measuresTabBarHeight()
            }
            .onPreferenceChange(TabBarHeightPreferenceKey.self) { tabBarHeight = $0 }
    }

    @ViewBuilder
    private var currentScreen: some View {
        switch selection {
        case .home: HomeView()
        case .lucid: LucidDreamView()
        case .journal: DreamJournalView()
        case .progress: StatsView()
        case .profile: ProfileView()
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
