//
//  CustomTabBar.swift
//  HalfLight
//
//  Bottom navigation bar with one icon per destination.
//

import SwiftUI

struct CustomTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                tabButton(tab)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(
            Rectangle()
                .fill(Color.dreamBase)
                .ignoresSafeArea(edges: .bottom)
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.dreamText.opacity(0.08))
                .frame(height: 1)
        }
    }

    private func tabButton(_ tab: AppTab) -> some View {
        let isSelected = selection == tab
        return Button {
            guard selection != tab else { return }
            // Update the selection first so the icon lights up this same frame —
            // the tap sound (which can spin up the audio engine on first use) runs
            // after, never gating the visual feedback.
            selection = tab
            SoundManager.shared.play(.tap)
        } label: {
            Image(systemName: tab.icon)
                .font(.system(size: 22))
                .foregroundStyle(isSelected ? Color.dreamPrimary : .secondary)
                .scaleEffect(isSelected ? 1.05 : 1.0)
                // Soft halo behind the active icon plus a colored glow on it.
                .background {
                    Circle()
                        .fill(Color.dreamPrimary)
                        .frame(width: 34, height: 34)
                        .blur(radius: 12)
                        .opacity(isSelected ? 0.4 : 0)
                }
                .shadow(color: Color.dreamPrimary.opacity(isSelected ? 0.55 : 0), radius: 6)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                // The icon's own quick animation — independent of (and faster than)
                // the screen crossfade — so the glow snaps on the instant you tap.
                .animation(.easeOut(duration: 0.1), value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
    }
}
