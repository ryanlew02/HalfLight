//
//  StatsView.swift
//  HalfLight
//
//  Simple insights computed from the dream library.
//

import SwiftUI
import SwiftData

struct StatsView: View {
    @Query private var dreams: [Dream]

    var body: some View {
        NavigationStack {
            Group {
                if dreams.isEmpty {
                    ContentUnavailableView(
                        "No Stats Yet",
                        systemImage: "chart.bar",
                        description: Text("Record a few dreams to see patterns here.")
                    )
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 28) {
                            moodSection
                            tagSection
                        }
                        .padding(20)
                    }
                }
            }
            .background { DreamBackground() }
            .navigationTitle("Stats")
        }
    }

    // MARK: - Moods

    private var moodSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Moods")
                .font(.headline)
            ForEach(moodCounts, id: \.mood) { item in
                HStack(spacing: 12) {
                    Label(item.mood.rawValue, systemImage: item.mood.symbol)
                        .font(.subheadline)
                        .foregroundStyle(item.mood.tint)
                        .frame(width: 130, alignment: .leading)

                    GeometryReader { geo in
                        Capsule()
                            .fill(item.mood.tint.opacity(0.3))
                            .frame(width: barWidth(for: item.count, in: geo.size.width))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 14)

                    Text("\(item.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 28, alignment: .trailing)
                }
            }
        }
    }

    // MARK: - Tags

    @ViewBuilder
    private var tagSection: some View {
        if !topTags.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Top themes")
                    .font(.headline)
                ForEach(topTags, id: \.tag) { item in
                    HStack {
                        Text(item.tag)
                        Spacer()
                        Text("\(item.count)")
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }
            }
        }
    }

    // MARK: - Computed data

    private var moodCounts: [(mood: Dream.Mood, count: Int)] {
        Dream.Mood.allCases.map { mood in
            (mood, dreams.filter { $0.mood == mood }.count)
        }
    }

    private var topTags: [(tag: String, count: Int)] {
        let counts = Dictionary(grouping: dreams.flatMap(\.tags), by: { $0 })
            .mapValues(\.count)
        return counts
            .sorted { $0.value > $1.value }
            .prefix(8)
            .map { (tag: $0.key, count: $0.value) }
    }

    private func barWidth(for count: Int, in fullWidth: CGFloat) -> CGFloat {
        let maxCount = moodCounts.map(\.count).max() ?? 0
        guard maxCount > 0, count > 0 else { return 0 }
        let fraction = CGFloat(count) / CGFloat(maxCount)
        return max(8, fullWidth * fraction)
    }
}

#Preview {
    StatsView()
        .modelContainer(PreviewData.container)
        .environment(PreviewData.store)
}
