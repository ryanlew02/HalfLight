//
//  CustomTabBar.swift
//  HalfLight
//
//  Bottom navigation bar with a raised center "+" for adding a dream.
//

import SwiftUI

struct CustomTabBar: View {
    @Binding var selection: AppTab
    let onAdd: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            tabButton(.home)
            tabButton(.journal)
            addButton
            tabButton(.lucid)
            tabButton(.stats)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
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
            selection = tab
        } label: {
            VStack(spacing: 4) {
                Image(systemName: tab.icon)
                    .font(.system(size: 20))
                Text(tab.title)
                    .font(.caption2)
            }
            .foregroundStyle(selection == tab ? Color.dreamPrimary : .secondary)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
    }

    private var addButton: some View {
        Button(action: onAdd) {
            Image(systemName: "plus")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(
                    LinearGradient(
                        colors: [.dreamPrimary, .dreamAccent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: .circle
                )
                .shadow(color: Color.dreamPrimary.opacity(0.5), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .offset(y: -14)
        .accessibilityLabel("Add Dream")
    }
}
