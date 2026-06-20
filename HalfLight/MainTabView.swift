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
    @State private var router = AppRouter()
    @State private var tabBarHeight: CGFloat = 0

    var body: some View {
        @Bindable var router = router
        ZStack {
            currentScreen
                .id(router.tab)
                .transition(.opacity)
        }
            .foregroundStyle(Color.dreamText)
            .environment(\.tabBarHeight, tabBarHeight)
            .environment(router)
            .safeAreaInset(edge: .bottom) {
                CustomTabBar(selection: $router.tab)
                    .measuresTabBarHeight()
            }
            .onPreferenceChange(TabBarHeightPreferenceKey.self) { tabBarHeight = $0 }
            .overlay {
                if let reward = router.claimReward {
                    XPClaimView(reward: reward) { router.dismissClaim() }
                        .transition(.opacity)
                        .zIndex(10)
                }
            }
    }

    @ViewBuilder
    private var currentScreen: some View {
        switch router.tab {
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
