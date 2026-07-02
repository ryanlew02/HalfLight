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

    /// How the gallery is ordered. Persisted so the choice sticks between visits.
    @AppStorage("achievementsSort") private var sortOption: SortOption = .featured

    private let columns = [GridItem(.flexible(), spacing: DreamMetric.md),
                           GridItem(.flexible(), spacing: DreamMetric.md)]

    /// The ways the badge gallery can be ordered.
    enum SortOption: String, CaseIterable, Identifiable {
        case featured       // curated ladder order (the default)
        case recent         // most recently unlocked first
        case closest        // nearest to unlocking first
        case reward         // highest XP payout first

        var id: String { rawValue }

        var label: String {
            switch self {
            case .featured: "Featured"
            case .recent: "Recently unlocked"
            case .closest: "Closest to unlock"
            case .reward: "Highest reward"
            }
        }

        var systemImage: String {
            switch self {
            case .featured: "sparkles"
            case .recent: "clock.arrow.circlepath"
            case .closest: "target"
            case .reward: "star.fill"
            }
        }
    }

    private var unlockedCount: Int {
        Achievement.all.filter { $0.isUnlocked(for: stats) }.count
    }

    /// Stable catalog position per badge, used to break ties deterministically.
    private var catalogIndex: [String: Int] {
        Dictionary(uniqueKeysWithValues: Achievement.all.enumerated().map { ($0.element.id, $0.offset) })
    }

    private var sortedAchievements: [Achievement] {
        switch sortOption {
        case .featured:
            return Achievement.all
        case .recent:
            return AchievementTracker.sortedByRecency(for: stats)
        case .closest:
            let index = catalogIndex
            return Achievement.all.sorted { lhs, rhs in
                let lUnlocked = lhs.isUnlocked(for: stats)
                let rUnlocked = rhs.isUnlocked(for: stats)
                // Still-earnable badges first, nearest completion at the top.
                if lUnlocked != rUnlocked { return !lUnlocked }
                let lf = lhs.fraction(for: stats), rf = rhs.fraction(for: stats)
                if lf != rf { return lf > rf }
                return (index[lhs.id] ?? 0) < (index[rhs.id] ?? 0)
            }
        case .reward:
            let index = catalogIndex
            return Achievement.all.sorted { lhs, rhs in
                if lhs.xp != rhs.xp { return lhs.xp > rhs.xp }
                return (index[lhs.id] ?? 0) < (index[rhs.id] ?? 0)
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DreamMetric.xl) {
                Text("\(unlockedCount) of \(Achievement.all.count) unlocked")
                    .font(.dreamCaption)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: columns, spacing: DreamMetric.md) {
                    ForEach(sortedAchievements) { achievement in
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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                sortMenu
            }
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort by", selection: $sortOption) {
                ForEach(SortOption.allCases) { option in
                    Label(option.label, systemImage: option.systemImage).tag(option)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.dreamPrimary)
        }
        .accessibilityLabel("Sort achievements")
    }
}

/// A single badge tile: icon medallion, title, and either a "complete" mark or a
/// progress bar with the current/goal count.
struct AchievementBadge: View {
    let achievement: Achievement
    let stats: AchievementStats

    var body: some View {
        // Resolve unlock state and progress once per render — these walk the
        // dreamer's stats, so recomputing them several times per tile (and across
        // a gridful of tiles) is wasted work while scrolling.
        let unlocked = achievement.isUnlocked(for: stats)

        return VStack(spacing: DreamMetric.sm) {
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
        // A flat card (no large colored glow): the medallion's own halo already
        // marks a badge as earned, and dropping the big per-tile shadow keeps the
        // grid smooth to scroll. Locked state reads from the muted medallion and
        // secondary text — whole-tile fractional opacity would force an offscreen
        // compositing pass per locked tile.
        .dreamCard()
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
    /// Soft colored halo behind earned badges. On by default for the gallery; turn
    /// it off where the badges should sit flatter (e.g. a profile badge row).
    var bloom: Bool = true

    var body: some View {
        ZStack {
            // Colored disc when earned; a quiet muted disc while locked.
            Circle()
                .fill(discFill)
                .overlay(
                    // Top-down sheen so the disc reads as a lit, domed surface.
                    // A plain white gradient at reduced opacity — a soft-light
                    // blend mode here forced an offscreen render pass for every
                    // medallion, which added up across a scrolling gridful.
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(unlocked ? 0.28 : 0.06), .clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                )

            Image(systemName: unlocked ? symbol : "lock.fill")
                .font(.system(size: size * 0.4, weight: .bold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(glyphFill)
                .shadow(color: (unlocked && bloom) ? tint.opacity(0.55) : .clear,
                        radius: size * 0.03, y: size * 0.02)
        }
        .frame(width: size, height: size)
        // Framing ring just inside the edge.
        .overlay(
            Circle().strokeBorder(ringFill, lineWidth: max(1.5, size * 0.045))
        )
        // Soft colored bloom behind unlocked badges. A circular shadow gives the
        // same halo as the old blurred-circle background but is far cheaper to
        // composite while scrolling a gridful of medallions.
        .shadow(
            color: (unlocked && bloom) ? tint.opacity(0.5) : .clear,
            radius: size * 0.18,
            y: size * 0.03
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
