//
//  StatsView.swift
//  HalfLight
//
//  The "Progress" screen, pushed from the Profile tab: level/XP, weekly quests,
//  streak, achievements, and a per-year activity grid over the dream library.
//

import SwiftUI
import SwiftData

struct StatsView: View {
    @Environment(DreamStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Query private var dreams: [Dream]

    /// The calendar year shown in the activity grid; defaults to this year.
    @State private var selectedYear = Calendar.current.component(.year, from: .now)

    /// Measured width of the achievements strip, used to size the medallions so
    /// the row always fits the card instead of overflowing it.
    @State private var medallionStripWidth: CGFloat = 0

    var body: some View {
        // Pushed as a destination from the Profile tab, so it uses that
        // NavigationStack rather than wrapping its own.
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        progressSection
                        bonusBanner
                        questsSection
                            .id(Self.questsAnchor)
                        streakSection
                        achievementsSection
                        if dreams.isEmpty {
                            emptyHint
                        } else {
                            activitySection
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 20)
                }
                .tabBarClearance()
            }
            .background { DreamBackground() }
            .toolbar(.hidden, for: .navigationBar)
            // Hiding the nav bar disables the edge-swipe back gesture; put it back.
            .enableSwipeBack()
            .onAppear { consumeQuestScrollIntent(proxy) }
            .onChange(of: router.scrollToQuests) { _, _ in
                consumeQuestScrollIntent(proxy)
            }
        }
    }

    /// Back chevron followed by a left-aligned `.dreamTitle` heading, matching the
    /// Feed / Journal / Lucid Path headers (the system nav bar is hidden so the
    /// title isn't squeezed into a truncated toolbar bubble).
    private var header: some View {
        HStack(spacing: 12) {
            Button {
                SoundManager.shared.play(.tap)
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.dreamText)
            }
            .accessibilityLabel("Back")

            Text("Progress")
                .font(.dreamTitle)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 12)
    }

    /// Scroll anchor for the weekly-quests card, used when arriving from the Home
    /// quest shortcut.
    private static let questsAnchor = "quests"

    /// Honor a pending "scroll to quests" request from the Home shortcut, then
    /// clear it. Deferred a beat so the freshly-shown layout is ready to scroll.
    private func consumeQuestScrollIntent(_ proxy: ScrollViewProxy) {
        guard router.scrollToQuests else { return }
        router.scrollToQuests = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeInOut) {
                proxy.scrollTo(Self.questsAnchor, anchor: .top)
            }
        }
    }

    // MARK: - Progress (XP & level)

    /// Completed lucid lessons, kept in sync by `LucidProgress`; folded into XP.
    @AppStorage("lucidSectionsCompleted") private var lucidSectionsCompleted = 0

    /// XP banked from completed weekly quests, accumulated across weeks. Folded
    /// into `totalXP` so quests level the dreamer up like everything else.
    @AppStorage("questBankedXP") private var questBankedXP = 0

    private var totalXP: Int {
        store.totalXP(
            dreams: dreams,
            lucidSections: lucidSectionsCompleted,
            questBankedXP: questBankedXP
        )
    }
    private var level: Int { DreamProgression.level(forXP: totalXP) }
    private var xpIntoLevel: Int { DreamProgression.xpIntoLevel(forXP: totalXP) }
    private var xpForLevel: Int { DreamProgression.xpForCurrentLevel(forXP: totalXP) }
    private var levelProgress: Double { DreamProgression.progress(forXP: totalXP) }
    private var rank: DreamProgression.Rank { DreamProgression.rank(forLevel: level) }
    private var streak: Streak { Streak.from(journaledDays: journaledDays) }

    private var progressSection: some View {
        // `totalXP` walks every dream and all 40 achievements, so compute it once
        // and derive level/rank/progress from that single value (cheap int math)
        // instead of recomputing it for each readout.
        let totalXP = self.totalXP
        let level = DreamProgression.level(forXP: totalXP)
        let rank = DreamProgression.rank(forLevel: level)
        let xpIntoLevel = DreamProgression.xpIntoLevel(forXP: totalXP)
        let xpForLevel = DreamProgression.xpForCurrentLevel(forXP: totalXP)
        let levelProgress = DreamProgression.progress(forXP: totalXP)

        return NavigationLink {
            LevelsView(totalXP: totalXP)
        } label: {
            VStack(alignment: .leading, spacing: DreamMetric.md) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(localized(rank.name))
                            .font(.dreamDisplay(18, .bold))
                        Text("Level \(level)")
                            .font(.dreamBody(12, .semibold))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(totalXP) XP")
                        .font(.dreamBody(13, .semibold))
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.dreamText.opacity(0.4))
                }

                SegmentedProgressBar(progress: levelProgress)
                    .frame(height: 16)

                Text("\(xpIntoLevel) / \(xpForLevel) XP to Level \(level + 1)")
                    .font(.dreamBody(12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DreamMetric.lg)
            .dreamCard()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Streak

    private var streakSection: some View {
        let streak = self.streak
        return HStack(spacing: DreamMetric.md) {
            streakCard(value: streak.current, label: "Current streak", icon: "flame.fill")
            streakCard(value: streak.longest, label: "Highest streak", icon: "trophy.fill")
        }
    }

    private func streakCard(value: Int, label: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: DreamMetric.sm) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.dreamPrimary)
            Text(value == 1 ? "1 day" : "\(value) days")
                .font(.dreamDisplay(22, .bold))
            Text(label)
                .font(.dreamBody(12, .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DreamMetric.lg)
        .dreamCard()
    }

    // MARK: - Weekly quests

    /// Start of the current week (Monday), shared by the stats and the XP banking.
    private var weekStart: Date { Quest.weekStart() }

    /// Dreams recorded since the start of this week.
    private var weekDreams: [Dream] {
        dreams.filter { $0.date >= weekStart }
    }

    /// Journaled days (recorded or "can't remember") falling in this week.
    private var journaledDaysThisWeek: Int {
        journaledDays.filter { $0 >= weekStart }.count
    }

    /// Metrics every active quest is measured against.
    private var questStats: QuestStats {
        QuestStats(
            weekDreams: weekDreams,
            journaledDaysThisWeek: journaledDaysThisWeek,
            currentStreak: streak.current
        )
    }

    /// The five quests drawn for the current week.
    private var weeklyQuests: [Quest] { Quest.weekly() }

    /// Claim a completed quest's XP: bank it and fire the reward animation.
    private func claim(_ quest: Quest) {
        guard QuestRewards.isClaimable(quest, stats: questStats, weekStart: weekStart) else { return }
        questBankedXP = QuestRewards.claim(quest, weekStart: weekStart, currentTotal: questBankedXP)
        router.presentClaim(xp: quest.xp, title: quest.title)
    }

    /// Claim the "all quests complete" bonus.
    private func claimBonus() {
        guard QuestRewards.isBonusClaimable(quests: weeklyQuests, stats: questStats, weekStart: weekStart) else {
            return
        }
        questBankedXP = QuestRewards.claimBonus(weekStart: weekStart, currentTotal: questBankedXP)
        router.presentClaim(xp: Quest.allCompleteBonusXP, title: "All Quests Complete!")
    }

    @ViewBuilder
    private var bonusBanner: some View {
        let stats = questStats
        let quests = weeklyQuests
        if QuestRewards.isBonusClaimable(quests: quests, stats: stats, weekStart: weekStart) {
            Button { claimBonus() } label: {
                HStack(spacing: DreamMetric.sm) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 16, weight: .bold))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("All quests complete!")
                            .font(.dreamBody(14, .bold))
                        Text("Claim your bonus")
                            .font(.dreamBody(11))
                            .foregroundStyle(Color.white.opacity(0.85))
                    }
                    Spacer(minLength: 8)
                    Text("+\(Quest.allCompleteBonusXP) XP")
                        .font(.dreamBody(14, .bold))
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, DreamMetric.md)
                .padding(.vertical, DreamMetric.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(
                        colors: [Color.dreamPrimary, Color.dreamAccent],
                        startPoint: .leading, endPoint: .trailing
                    ),
                    in: .rect(cornerRadius: DreamMetric.controlRadius)
                )
                .shadow(color: Color.dreamPrimary.opacity(0.4), radius: 10, y: 4)
            }
            .buttonStyle(.plain)
        } else if QuestRewards.isBonusClaimed(weekStart: weekStart) {
            HStack(spacing: DreamMetric.sm) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 14, weight: .bold))
                Text("All quests complete — bonus claimed")
                    .font(.dreamBody(12, .semibold))
                Spacer()
            }
            .foregroundStyle(Color.dreamPrimary)
            .padding(.horizontal, DreamMetric.md)
            .padding(.vertical, DreamMetric.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.dreamPrimary.opacity(0.12), in: .rect(cornerRadius: DreamMetric.controlRadius))
        }
    }

    private var questsSection: some View {
        let stats = questStats
        let quests = weeklyQuests
        let claimedCount = quests.filter { QuestRewards.isClaimed($0, weekStart: weekStart) }.count

        return VStack(alignment: .leading, spacing: DreamMetric.md) {
            HStack(alignment: .firstTextBaseline) {
                Text("Weekly Quests")
                    .font(.dreamDisplay(18, .bold))
                Spacer()
                Text(Quest.resetText)
                    .font(.dreamBody(12, .semibold))
                    .foregroundStyle(.secondary)
            }

            Text("\(claimedCount) of \(quests.count) claimed")
                .font(.dreamBody(12))
                .foregroundStyle(.secondary)

            VStack(spacing: DreamMetric.md) {
                ForEach(Array(quests.enumerated()), id: \.element.id) { index, quest in
                    if index > 0 {
                        Rectangle()
                            .fill(Color.dreamText.opacity(0.08))
                            .frame(height: 1)
                    }
                    QuestRow(
                        quest: quest,
                        stats: stats,
                        claimed: QuestRewards.isClaimed(quest, weekStart: weekStart),
                        onClaim: { claim(quest) }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DreamMetric.lg)
        .dreamCard()
    }

    // MARK: - Achievements

    /// Metrics every badge is evaluated against, rebuilt from the current library.
    private var achievementStats: AchievementStats {
        AchievementStats(
            dreams: dreams,
            journaledDays: journaledDays,
            lucidSections: lucidSectionsCompleted
        )
    }

    /// A short teaser for the Progress card: with 40 badges we can't show them
    /// all, so surface the unlocked ones first, then the locked badges nearest
    /// completion, capped to a single tidy row. Takes a prebuilt `stats` value so
    /// the (expensive) stats aren't recomputed for every comparison in the sort.
    private func previewAchievements(_ stats: AchievementStats) -> [Achievement] {
        let unlocked = Achievement.all.filter { $0.isUnlocked(for: stats) }
        let lockedByProgress = Achievement.all
            .filter { !$0.isUnlocked(for: stats) }
            .sorted { $0.fraction(for: stats) > $1.fraction(for: stats) }
        return Array((unlocked + lockedByProgress).prefix(6))
    }

    /// Medallion side length that lets `count` previewed badges fit the measured
    /// strip width, capped so they don't balloon on wide screens.
    private func medallionSize(count: Int) -> CGFloat {
        // Zero until the strip width is measured: a zero-size badge for one
        // layout pass can't overflow the card, whereas a non-zero guess could.
        guard count > 0, medallionStripWidth > 0 else { return 0 }
        let totalSpacing = DreamMetric.sm * CGFloat(count - 1)
        return min(40, (medallionStripWidth - totalSpacing) / CGFloat(count))
    }

    private var achievementsSection: some View {
        // Build the stats once, then reuse the value everywhere below — each call
        // to `isUnlocked`/`fraction` is then O(1) instead of rebuilding the stats
        // (which walks every dream) per badge and per sort comparison.
        let stats = achievementStats
        let preview = previewAchievements(stats)
        let unlockedCount = Achievement.all.reduce(0) { $0 + ($1.isUnlocked(for: stats) ? 1 : 0) }
        let size = medallionSize(count: preview.count)

        return NavigationLink {
            AchievementsView(stats: stats)
        } label: {
            VStack(alignment: .leading, spacing: DreamMetric.md) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Achievements")
                        .font(.dreamDisplay(18, .bold))
                    Spacer()
                    Text("\(unlockedCount) / \(Achievement.all.count)")
                        .font(.dreamBody(13, .semibold))
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.dreamText.opacity(0.4))
                }

                // A medallion strip: unlocked badges shine in their tint, the
                // rest stay as muted locks to hint at what's still to earn.
                // The badge size is derived from the measured width so the row
                // always fits inside the card and the strip only takes the
                // vertical space the medallions actually need.
                HStack(spacing: DreamMetric.sm) {
                    ForEach(preview) { achievement in
                        AchievementMedallion(
                            symbol: achievement.symbol,
                            tint: achievement.tint,
                            unlocked: achievement.isUnlocked(for: stats),
                            size: size
                        )
                        .frame(maxWidth: .infinity)
                    }
                }
                // Fill the available width so the background reads the card's
                // content width, not the medallions' own width — otherwise the
                // measurement feeds back into the size and the row overflows.
                .frame(maxWidth: .infinity)
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onAppear { medallionStripWidth = geo.size.width }
                            .onChange(of: geo.size.width) { _, width in medallionStripWidth = width }
                    }
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DreamMetric.lg)
            .dreamCard()
        }
        .buttonStyle(.plain)
    }

    private var emptyHint: some View {
        Text("Record a few dreams to unlock your activity.")
            .font(.dreamBodyText)
            .foregroundStyle(.secondary)
            .dreamBodyLineSpacing()
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Activity (past year)

    /// Side length of each day square, in points.
    private let squareSize: CGFloat = 11
    private let squareSpacing: CGFloat = 3

    private var activitySection: some View {
        let weeks = weeks(for: selectedYear)
        // Build the journaled-days set ONCE for the whole grid; it was previously
        // rebuilt from every dream inside each of the ~370 day squares.
        let journaled = journaledDays
        return VStack(alignment: .leading, spacing: DreamMetric.md) {
            Text("Activity")
                .font(.dreamSectionHeader)

            HStack(spacing: DreamMetric.md) {
                yearArrow(systemName: "chevron.left", enabled: selectedYear > earliestYear) {
                    selectedYear -= 1
                }

                Text(String(selectedYear))
                    .font(.dreamCardTitle)
                    .monospacedDigit()

                yearArrow(systemName: "chevron.right", enabled: selectedYear < currentYear) {
                    selectedYear += 1
                }

                Spacer()

                Text("\(daysJournaledCount(in: journaled, for: selectedYear)) days journaled")
                    .font(.dreamCaption)
                    .foregroundStyle(.secondary)
            }

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: squareSpacing) {
                        ForEach(Array(weeks.enumerated()), id: \.offset) { index, week in
                            weekColumn(week, journaled: journaled)
                                .id(index)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .onAppear { scrollToEdge(proxy, weekCount: weeks.count) }
                .onChange(of: selectedYear) { _, _ in scrollToEdge(proxy, weekCount: weeks.count) }
            }
        }
    }

    /// A year-paging chevron. When it can't be used it's dimmed darker so the
    /// available direction reads as the brighter, tappable one.
    private func yearArrow(systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(enabled ? Color.dreamPrimary : Color.dreamText.opacity(0.25))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    /// Jump to the most recent week for the current year, or the start of the
    /// year for past years.
    private func scrollToEdge(_ proxy: ScrollViewProxy, weekCount: Int) {
        if selectedYear == currentYear {
            proxy.scrollTo(weekCount - 1, anchor: .trailing)
        } else {
            proxy.scrollTo(0, anchor: .leading)
        }
    }

    /// One week's column of day squares, drawn in a single `Canvas` so the grid
    /// is ~53 lightweight draw passes instead of ~370 individual shape views — the
    /// difference that keeps the Progress screen smooth while scrolling. Journaled
    /// days fill in the accent; other real days get a faint outline; padding cells
    /// (nil, outside the year) stay blank.
    private func weekColumn(_ week: [Date?], journaled: Set<Date>) -> some View {
        let height = squareSize * 7 + squareSpacing * 6
        return Canvas { context, _ in
            for (row, day) in week.enumerated() {
                guard let day else { continue }
                let y = CGFloat(row) * (squareSize + squareSpacing)
                let path = Path(
                    roundedRect: CGRect(x: 0, y: y, width: squareSize, height: squareSize),
                    cornerRadius: 2
                )
                if journaled.contains(day) {
                    context.fill(path, with: .color(.dreamPrimary))
                } else {
                    context.stroke(path, with: .color(.dreamText.opacity(0.12)), lineWidth: 1)
                }
            }
        }
        .frame(width: squareSize, height: height)
    }

    // MARK: - Computed data

    /// Calendar days that count as journaled: a dream was recorded, or the user
    /// tapped "I'm not sure" on the home prompt. Normalized to start-of-day.
    private var journaledDays: Set<Date> {
        let calendar = Calendar.current
        let dreamDays = dreams.map { calendar.startOfDay(for: $0.date) }
        return Set(dreamDays).union(store.skippedDays)
    }

    private var currentYear: Int {
        Calendar.current.component(.year, from: .now)
    }

    /// How far back the user can page: always at least 2024, or earlier if there
    /// happens to be journaled data before then.
    private var earliestYear: Int {
        let earliestData = journaledDays
            .map { Calendar.current.component(.year, from: $0) }
            .min() ?? currentYear
        return min(2024, earliestData)
    }

    private func daysJournaledCount(in journaled: Set<Date>, for year: Int) -> Int {
        let calendar = Calendar.current
        return journaled.filter { calendar.component(.year, from: $0) == year }.count
    }

    /// A calendar year laid out as week columns of 7 days each. Leading/trailing
    /// slots that fall outside the year are `nil` so rows stay aligned by weekday.
    /// The current year stops at today rather than running to Dec 31.
    private func weeks(for year: Int) -> [[Date?]] {
        let calendar = Calendar.current
        guard let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let yearEnd = calendar.date(from: DateComponents(year: year, month: 12, day: 31))
        else { return [] }

        let today = calendar.startOfDay(for: .now)
        let end = min(yearEnd, today)

        // Back up to the start of the week so rows align by weekday.
        let leadingBlanks = calendar.component(.weekday, from: start) - calendar.firstWeekday
        let normalizedBlanks = (leadingBlanks + 7) % 7

        var days: [Date?] = Array(repeating: nil, count: normalizedBlanks)
        var day = start
        while day <= end {
            days.append(day)
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? end.addingTimeInterval(1)
        }
        // Pad the final week so the last column also has 7 rows.
        while days.count % 7 != 0 {
            days.append(nil)
        }

        return stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<$0 + 7]) }
    }
}

/// A level-style progress bar split into equal segments by notches, e.g.
/// `---|---|----|`. The gradient fill shows progress across the whole bar.
private struct SegmentedProgressBar: View {
    /// 0...1 fill fraction.
    let progress: Double
    var segments: Int = 5

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.dreamText.opacity(0.1))

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.dreamPrimary, .dreamAccent],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, min(1, progress)) * geo.size.width)

                // Notches between segments (cut in the track's base color).
                HStack(spacing: 0) {
                    ForEach(0..<(segments - 1), id: \.self) { _ in
                        Spacer(minLength: 0)
                        Rectangle()
                            .fill(Color.dreamSurface)
                            .frame(width: 2)
                    }
                    Spacer(minLength: 0)
                }
            }
            .clipShape(.capsule)
        }
    }
}

#Preview("Light") {
    NavigationStack {
        StatsView()
    }
    .modelContainer(PreviewData.container)
    .environment(PreviewData.store)
    .environment(AppRouter())
}

#Preview("Dark") {
    NavigationStack {
        StatsView()
    }
    .modelContainer(PreviewData.container)
    .environment(PreviewData.store)
    .environment(AppRouter())
    .preferredColorScheme(.dark)
}
