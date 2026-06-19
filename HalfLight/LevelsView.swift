//
//  LevelsView.swift
//  HalfLight
//
//  Pushed from the Profile progress card. Explains how to earn XP and lists the
//  named ranks, highlighting the one the dreamer currently holds.
//

import SwiftUI

struct LevelsView: View {
    let totalXP: Int

    private var level: Int { DreamProgression.level(forXP: totalXP) }
    private var currentRank: DreamProgression.Rank { DreamProgression.rank(forLevel: level) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                earnSection
                ranksSection
            }
            .padding(20)
        }
        .tabBarClearance()
        .background { DreamBackground() }
        .tint(.dreamPrimary)
        .navigationTitle("Levels")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Ways to earn XP

    private var earnSection: some View {
        VStack(alignment: .leading, spacing: DreamMetric.md) {
            Text("Ways to earn XP")
                .font(.dreamSectionHeader)

            earnRow(
                icon: "book.fill",
                title: "Record a dream",
                detail: "For every journal entry",
                xp: DreamProgression.xpPerJournalEntry
            )
            earnRow(
                icon: "moon.stars.fill",
                title: "Complete a lucid section",
                detail: "For each lesson on your lucid path",
                xp: DreamProgression.xpPerLucidSection
            )
            earnRow(
                icon: "rosette",
                title: "Unlock an achievement",
                detail: "Bonus XP scaling with each tier you reach",
                xp: nil
            )

            Text("Every \(DreamProgression.xpPerLevel) XP earns a new level.")
                .font(.dreamBody(12))
                .foregroundStyle(.secondary)
        }
    }

    /// `xp == nil` renders a "Varies" badge instead of a fixed amount, used for
    /// rewards (like achievements) whose value depends on what's earned.
    private func earnRow(icon: String, title: String, detail: String, xp: Int?) -> some View {
        HStack(spacing: DreamMetric.md) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.dreamPrimary)
                .frame(width: 44, height: 44)
                .background(Color.dreamPrimary.opacity(0.12), in: .circle)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.dreamRowTitle)
                Text(detail).font(.dreamBody(12)).foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Text(xp.map { "+\($0) XP" } ?? "Varies")
                .font(.dreamBody(14, .bold))
                .foregroundStyle(Color.dreamPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DreamMetric.lg)
        .dreamCard()
    }

    // MARK: - Ranks

    private var ranksSection: some View {
        VStack(alignment: .leading, spacing: DreamMetric.md) {
            Text("Levels")
                .font(.dreamSectionHeader)

            ForEach(DreamProgression.ranks) { rank in
                rankRow(rank)
            }
        }
    }

    private func rankRow(_ rank: DreamProgression.Rank) -> some View {
        let unlocked = level >= rank.minLevel
        let isCurrent = rank == currentRank

        return HStack(spacing: DreamMetric.md) {
            Image(systemName: unlocked ? "checkmark.seal.fill" : "lock.fill")
                .font(.system(size: 20))
                .foregroundStyle(unlocked ? Color.dreamPrimary : Color.dreamText.opacity(0.3))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(rank.name)
                    .font(.dreamRowTitle)
                Text("Level \(rank.minLevel)+")
                    .font(.dreamBody(12))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if isCurrent {
                Text("Current")
                    .font(.dreamBody(11, .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, DreamMetric.sm)
                    .padding(.vertical, 4)
                    .background(Color.dreamPrimary, in: .capsule)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DreamMetric.lg)
        .dreamCard(glow: isCurrent ? Color.dreamPrimary : nil)
        .opacity(unlocked ? 1 : 0.7)
    }
}

#Preview("Light") {
    NavigationStack {
        LevelsView(totalXP: 230)
    }
}

#Preview("Dark") {
    NavigationStack {
        LevelsView(totalXP: 230)
    }
    .preferredColorScheme(.dark)
}
