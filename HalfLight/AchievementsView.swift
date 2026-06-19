//
//  AchievementsView.swift
//  HalfLight
//
//  Full badge gallery, pushed from the Progress screen. Shows every achievement
//  with its unlock state and progress toward the ones still locked.
//

import SwiftUI

struct AchievementsView: View {
    let stats: AchievementStats

    private let columns = [GridItem(.flexible(), spacing: DreamMetric.md),
                           GridItem(.flexible(), spacing: DreamMetric.md)]

    private var unlockedCount: Int {
        Achievement.all.filter { $0.isUnlocked(for: stats) }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DreamMetric.xl) {
                Text("\(unlockedCount) of \(Achievement.all.count) unlocked")
                    .font(.dreamCaption)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: columns, spacing: DreamMetric.md) {
                    ForEach(Achievement.all) { achievement in
                        AchievementBadge(achievement: achievement, stats: stats)
                    }
                }
            }
            .padding(DreamMetric.screen)
        }
        .tabBarClearance()
        .background { DreamBackground() }
        .navigationTitle("Achievements")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A single badge tile: icon medallion, title, and either a "complete" mark or a
/// progress bar with the current/goal count.
struct AchievementBadge: View {
    let achievement: Achievement
    let stats: AchievementStats

    private var unlocked: Bool { achievement.isUnlocked(for: stats) }

    var body: some View {
        VStack(spacing: DreamMetric.sm) {
            AchievementMedallion(
                symbol: achievement.symbol,
                tint: achievement.tint,
                unlocked: unlocked,
                size: 68
            )

            Text(achievement.title)
                .font(.dreamDisplay(14, .bold))
                .multilineTextAlignment(.center)

            Text(achievement.detail)
                .font(.dreamBody(12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            // Absorb the uniform-height slack here so the status row sits at the
            // bottom of the tile instead of leaving dead space beneath it.
            Spacer(minLength: DreamMetric.sm)

            if unlocked {
                // Celebrate the reward already banked into the dreamer's total.
                Label("+\(achievement.xp) XP", systemImage: "checkmark.seal.fill")
                    .font(.dreamBody(11, .semibold))
                    .foregroundStyle(achievement.tint)
                    .padding(.top, 2)
            } else {
                VStack(spacing: 4) {
                    ProgressView(value: achievement.fraction(for: stats))
                        .tint(achievement.tint)
                    // Current progress plus the XP still waiting to be earned.
                    Text("\(achievement.current(for: stats)) / \(achievement.goal)  ·  +\(achievement.xp) XP")
                        .font(.dreamBody(10).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        // A floor that keeps tiles uniform without towering over their content;
        // the medallion + title + detail + status row sit just under this.
        .frame(minHeight: 165)
        .padding(DreamMetric.md)
        .dreamCard(glow: unlocked ? achievement.tint : nil)
        .opacity(unlocked ? 1 : 0.85)
    }
}

/// A glossy badge medallion that frames an SF Symbol in a custom shape: a
/// gradient-filled disc with a top-down sheen, a framing ring, and (when
/// unlocked) a soft colored bloom behind it. Sized parametrically so the same
/// treatment works small in the Progress-card strip and large in the gallery.
struct AchievementMedallion: View {
    let symbol: String
    let tint: Color
    let unlocked: Bool
    var size: CGFloat = 64

    var body: some View {
        ZStack {
            // Colored disc when earned; a quiet muted disc while locked.
            Circle()
                .fill(discFill)
                .overlay(
                    // Top-down sheen so the disc reads as a lit, domed surface.
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(unlocked ? 0.45 : 0.10), .clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                        .blendMode(.softLight)
                )

            Image(systemName: unlocked ? symbol : "lock.fill")
                .font(.system(size: size * 0.4, weight: .bold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(glyphFill)
                .shadow(color: unlocked ? tint.opacity(0.55) : .clear,
                        radius: size * 0.03, y: size * 0.02)
        }
        .frame(width: size, height: size)
        // Framing ring just inside the edge.
        .overlay(
            Circle().strokeBorder(ringFill, lineWidth: max(1.5, size * 0.045))
        )
        // Soft colored bloom behind unlocked badges.
        .background(
            Circle()
                .fill(tint)
                .blur(radius: size * 0.26)
                .opacity(unlocked ? 0.4 : 0)
        )
    }

    private var discFill: AnyShapeStyle {
        unlocked
            ? AnyShapeStyle(
                LinearGradient(
                    colors: [tint.opacity(0.95), tint.opacity(0.55)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            : AnyShapeStyle(Color.dreamText.opacity(0.07))
    }

    private var glyphFill: AnyShapeStyle {
        unlocked
            ? AnyShapeStyle(
                LinearGradient(
                    colors: [.white, .white.opacity(0.85)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            : AnyShapeStyle(Color.dreamText.opacity(0.35))
    }

    private var ringFill: AnyShapeStyle {
        unlocked
            ? AnyShapeStyle(
                LinearGradient(
                    colors: [.white.opacity(0.7), tint.opacity(0.3)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            : AnyShapeStyle(Color.dreamText.opacity(0.12))
    }
}

#Preview {
    NavigationStack {
        AchievementsView(
            stats: AchievementStats(
                dreams: Dream.makeSamples(),
                journaledDays: [],
                lucidSections: 1
            )
        )
    }
}
