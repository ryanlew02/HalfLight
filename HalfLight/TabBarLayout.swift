//
//  TabBarLayout.swift
//  HalfLight
//
//  The custom tab bar is attached with `.safeAreaInset` outside each screen's
//  NavigationStack, so its inset reaches root screens but NOT views pushed
//  within the stack. This plumbing lets the bar measure its own height, publish
//  it through the environment, and lets any pushed screen reserve matching room
//  with `.tabBarClearance()` — no hard-coded heights.
//

import SwiftUI

/// Measures the rendered height of the tab bar.
struct TabBarHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct TabBarHeightEnvironmentKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    /// The measured height of the custom tab bar, distributed so pushed screens
    /// can clear it. Zero until measured.
    var tabBarHeight: CGFloat {
        get { self[TabBarHeightEnvironmentKey.self] }
        set { self[TabBarHeightEnvironmentKey.self] = newValue }
    }
}

extension View {
    /// Reports this view's height into `TabBarHeightPreferenceKey` (attach to the tab bar).
    func measuresTabBarHeight() -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(key: TabBarHeightPreferenceKey.self, value: proxy.size.height)
            }
        )
    }

    /// Reserves bottom room equal to the tab bar height. Apply to scrollable
    /// content in screens pushed within a NavigationStack so the last items
    /// aren't hidden behind the bar.
    func tabBarClearance() -> some View {
        modifier(TabBarClearanceModifier())
    }
}

private struct TabBarClearanceModifier: ViewModifier {
    @Environment(\.tabBarHeight) private var tabBarHeight

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: tabBarHeight)
        }
    }
}
