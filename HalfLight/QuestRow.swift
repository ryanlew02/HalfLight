//
//  QuestRow.swift
//  HalfLight
//
//  One quest row — a status medallion, title + reward, the objective, and either
//  a progress bar, a Claim button (when complete but unclaimed), or a claimed
//  marker. Shared by the Progress screen's weekly-quests card.
//

import SwiftUI

struct QuestRow: View {
    let quest: Quest
    let stats: QuestStats
    /// Whether this quest's XP has already been claimed this week.
    var claimed: Bool = false
    /// Invoked when the dreamer taps Claim on a completed, unclaimed quest.
    var onClaim: (() -> Void)? = nil

    private var claimable: Bool { quest.isComplete(for: stats) && !claimed }

    var body: some View {
        HStack(alignment: .center, spacing: DreamMetric.md) {
            medallion

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(quest.title)
                        .font(.dreamBody(14, .semibold))
                        .foregroundStyle(Color.dreamText)
                    Spacer()
                    if !claimable {
                        Text("+\(quest.xp) XP")
                            .font(.dreamBody(12, .bold))
                            .foregroundStyle(claimed ? Color.dreamPrimary : Color.dreamText.opacity(0.45))
                    }
                }

                Text(quest.detail)
                    .font(.dreamBody(11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if claimable {
                    claimButton
                } else if claimed {
                    Label("Claimed", systemImage: "checkmark.seal.fill")
                        .font(.dreamBody(11, .semibold))
                        .foregroundStyle(Color.dreamPrimary)
                } else {
                    progress
                }
            }
        }
        .opacity(claimed ? 0.65 : 1)
    }

    private var medallion: some View {
        ZStack {
            Circle()
                .fill(quest.tint.opacity(claimable || claimed ? 0.9 : 0.14))
                .frame(width: 38, height: 38)
            Image(systemName: claimed ? "checkmark" : (claimable ? "gift.fill" : quest.symbol))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(claimable || claimed ? Color.white : quest.tint)
        }
    }

    private var claimButton: some View {
        Button {
            onClaim?()
        } label: {
            Text("Claim +\(quest.xp) XP")
                .font(.dreamBody(13, .bold))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    LinearGradient(
                        colors: [quest.tint, quest.tint.opacity(0.75)],
                        startPoint: .leading, endPoint: .trailing
                    ),
                    in: .capsule
                )
                .shadow(color: quest.tint.opacity(0.5), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
    }

    private var progress: some View {
        HStack(spacing: DreamMetric.sm) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.dreamText.opacity(0.1))
                    Capsule()
                        .fill(quest.tint)
                        .frame(width: max(0, geo.size.width * quest.fraction(for: stats)))
                }
            }
            .frame(height: 6)

            Text("\(quest.current(for: stats))/\(quest.goal)")
                .font(.dreamCaption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
        }
    }
}
