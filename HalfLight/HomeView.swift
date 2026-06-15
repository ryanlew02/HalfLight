//
//  HomeView.swift
//  HalfLight
//
//  Landing dashboard: a quick summary and the most recent dream.
//

import SwiftUI
import SwiftData

struct HomeView: View {
    @Query(sort: \Dream.date, order: .reverse) private var dreams: [Dream]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    greeting
                    summary
                    latest
                }
                .padding(20)
            }
            .background { DreamBackground() }
        }
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Welcome back")
                .font(.largeTitle.weight(.bold))
            Text("Capture your dreams before they fade.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summary: some View {
        HStack(spacing: 12) {
            SummaryCard(value: "\(dreams.count)", label: "Total dreams", icon: "book.fill")
            SummaryCard(value: "\(weekCount)", label: "This week", icon: "calendar")
        }
    }

    @ViewBuilder
    private var latest: some View {
        if let latest = dreams.first {
            VStack(alignment: .leading, spacing: 10) {
                Text("Latest dream")
                    .font(.headline)
                NavigationLink {
                    DreamDetailView(dream: latest)
                } label: {
                    DreamCard(dream: latest)
                }
                .buttonStyle(.plain)
            }
        } else {
            Text("No dreams yet — tap the + below to record your first.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
        }
    }

    private var weekCount: Int {
        let weekAgo = Date.now.addingTimeInterval(-7 * 24 * 60 * 60)
        return dreams.filter { $0.date >= weekAgo }.count
    }
}

/// A compact stat tile used on the Home dashboard.
private struct SummaryCard: View {
    let value: String
    let label: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(Color.dreamPrimary)
            Text(value)
                .font(.title.weight(.bold))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.dreamSurface, in: .rect(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.dreamText.opacity(0.08), lineWidth: 1)
        )
    }
}

#Preview {
    HomeView()
        .modelContainer(PreviewData.container)
        .environment(PreviewData.store)
}
