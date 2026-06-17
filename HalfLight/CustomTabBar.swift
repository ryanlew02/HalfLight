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
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                selection = tab
            }
        } label: {
            Image(systemName: tab.icon)
                .font(.system(size: 22))
                .foregroundStyle(selection == tab ? Color.dreamPrimary : .secondary)
                .scaleEffect(selection == tab ? 1.1 : 1.0)
                .symbolEffect(.bounce, value: selection == tab)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
    }
}
