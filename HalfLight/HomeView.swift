//
//  HomeView.swift
//  HalfLight
//
//  Landing dashboard, editorial / celestial redesign. A serif greeting and
//  full-width capture CTA sit above the latest-dream hero (lit by a mood-aura
//  orb); two big serif stats and a week tracker follow, then a single
//  "wander back" random-dream tile. Color = mood is the throughline.
//

import SwiftUI
import SwiftData
import WidgetKit

struct HomeView: View {
    @Environment(DreamStore.self) private var store
    @Environment(AuthService.self) private var auth
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Dream.date, order: .reverse) private var dreams: [Dream]

    @AppStorage("userName") private var userName = "Dreamer"
    /// The day (start-of-day, as a time interval) the user last tapped "I'm not sure".
    @AppStorage("dreamPromptSkippedDay") private var skippedDay: Double = 0
    /// XP banked from completed weekly quests; updated here so progress still counts
    /// when the dreamer only visits Home.
    @AppStorage("questBankedXP") private var questBankedXP = 0
    @AppStorage("lucidSectionsCompleted") private var lucidSectionsCompleted = 0
    @State private var isAddingDream = false
    /// Brief "come back tomorrow" confirmation after tapping "couldn't remember".
    @State private var showSkippedMessage = false
    /// The dream picked by "Surprise me"; setting it pushes the detail view.
    @State private var randomDream: Dream?
    /// Presents the account sheet from the "Create an account" tip.
    @State private var showAuth = false
    /// Whether the dreamer has added any HalfLight Lock Screen (accessory) widget —
    /// resolves the Lock Screen widget tip. Refreshed from WidgetKit on appear and
    /// when the app returns to the foreground (e.g. after adding one).
    @State private var hasLockScreenWidget = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    brandRow
                    greeting
                    captureCTA
                    if showTodayPrompt {
                        forgotButton
                    } else if showSkippedMessage {
                        skippedMessage
                            .transition(.opacity)
                    }

                    if dreams.isEmpty {
                        emptyState
                    } else {
                        latestSection
                        statsRow
                        questPreview
                        weekTracker
                        if dreams.count >= 2 {
                            randomDreamTile
                        }
                        achievementsSection
                    }

                    tipsSection
                }
                .padding(.horizontal, DreamMetric.screen)
                .padding(.top, DreamMetric.sm)
                .padding(.bottom, DreamMetric.xl)
            }
            .tabBarClearance()
            .background { DreamBackground() }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { refreshLockScreenWidgetTip() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { refreshLockScreenWidgetTip() }
            }
            .navigationDestination(item: $randomDream) { dream in
                DreamDetailView(dream: dream)
            }
            .sheet(isPresented: $showAuth) {
                AuthView()
            }
            .fullScreenCover(isPresented: $isAddingDream) {
                AddDreamView { draft in
                    // A day earns journaling XP only once; celebrate it only when
                    // this dream is what crosses that line for today.
                    let earnedXP = !hasJournalXPToday
                    store.add(draft)
                    if earnedXP {
                        router.presentClaim(
                            xp: DreamProgression.xpPerJournaledDay,
                            title: "Dream logged for today",
                            headline: "Dream Logged"
                        )
                    }
                }
            }
        }
    }

    // MARK: - Brand row

    private var brandRow: some View {
        HStack {
            HStack(spacing: 9) {
                BrandMark()
                Text("HALFLIGHT")
                    .font(.dreamMono(12, .medium))
                    .tracking(3)
                    .foregroundStyle(Color.dreamFaint)
            }
            Spacer()
            Text(Date.now, format: .dateTime.weekday(.abbreviated).month(.twoDigits).day())
                .font(.dreamMono(11))
                .tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(Color.dreamFaint)
        }
    }

    // MARK: - Greeting

    private var greetingText: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: localized("Good morning")
        case 12..<17: localized("Good afternoon")
        case 17..<22: localized("Good evening")
        default: localized("Good night")
        }
    }

    private var greetingEyebrow: String {
        dreams.isEmpty
            ? localized("Your dream journal")
            : localized("%lld dreams remembered", dreams.count)
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(greetingEyebrow)
            (
                Text("\(greetingText),\n")
                    .font(.dreamSerif(38))
                    .foregroundColor(.dreamText)
                + Text(userName)
                    .font(.dreamSerif(38, italic: true))
                    .foregroundColor(.dreamNameAccent)
            )
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Capture CTA

    private var loggedToday: Int {
        dreams.filter { Calendar.current.isDateInToday($0.date) }.count
    }

    private var captureCTA: some View {
        Button {
            isAddingDream = true
        } label: {
            HStack(spacing: 14) {
                Text("+")
                    .font(.dreamSerif(26))
                    .foregroundStyle(Color.dreamCTAGlyph)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Capture tonight's dream")
                        .font(.dreamGrotesk(15, .semibold))
                        .foregroundStyle(Color.dreamOnCTA)
                    Text("before it fades — \(loggedToday) logged today")
                        .font(.dreamMono(10))
                        .tracking(0.5)
                        .foregroundStyle(Color.dreamOnCTASub)
                }
                Spacer(minLength: 0)
                Text("→")
                    .font(.dreamGrotesk(18))
                    .foregroundStyle(Color.dreamCTAGlyph)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.dreamCTAFill, in: .rect(cornerRadius: DreamMetric.ctaRadius))
        }
        .buttonStyle(PressableTileStyle())
    }

    // MARK: - Today prompt (skip / "can't remember")

    private var hasDreamToday: Bool {
        dreams.contains { Calendar.current.isDateInToday($0.date) }
    }

    /// Whether today has already banked its once-per-day journaling XP — via a
    /// recorded dream, a "can't remember" skip, or a credit left by a deleted
    /// dream. Used to fire the reward popup only when XP is genuinely earned.
    private var hasJournalXPToday: Bool {
        let today = Calendar.current.startOfDay(for: .now)
        if hasDreamToday { return true }
        return store.skippedDays.contains(today) || store.creditedDays.contains(today)
    }

    private var skippedToday: Bool {
        guard skippedDay > 0 else { return false }
        return Calendar.current.isDateInToday(Date(timeIntervalSince1970: skippedDay))
    }

    private var showTodayPrompt: Bool { !hasDreamToday && !skippedToday }

    /// Mark today as journaled even though no dream was recorded ("can't
    /// remember"), so the streak survives the gap.
    private func markForgotten() {
        let earnedXP = !hasJournalXPToday
        skippedDay = Calendar.current.startOfDay(for: .now).timeIntervalSince1970
        store.recordSkippedDay()
        // Push the new "can't remember" day to the account so the streak follows
        // immediately, picking up any other-device progress in the same round-trip.
        Task { if await auth.syncProgressState() { store.refreshDayLogs() } }
        if earnedXP {
            // The button's style plays the press tap; reward popup adds its sound.
            router.presentClaim(
                xp: DreamProgression.xpPerJournaledDay,
                title: "Showed up for your dreams",
                headline: "Day Logged"
            )
        }
        withAnimation { showSkippedMessage = true }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { showSkippedMessage = false }
        }
    }

    /// A secondary action paired with the capture CTA: log the night as
    /// forgotten when there's no dream to capture.
    private var forgotButton: some View {
        Button(action: markForgotten) {
            HStack(spacing: 8) {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 12))
                Text("I forgot tonight's dream")
                    .font(.dreamGrotesk(14, .medium))
            }
            .foregroundStyle(Color.dreamSubtle)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(Color.dreamText.opacity(0.04), in: .rect(cornerRadius: DreamMetric.ctaRadius))
            .overlay(
                RoundedRectangle(cornerRadius: DreamMetric.ctaRadius)
                    .strokeBorder(Color.dreamText.opacity(0.10), lineWidth: 1)
            )
        }
        .buttonStyle(PressableTileStyle())
        .padding(.top, -14)
    }

    private var skippedMessage: some View {
        HStack(spacing: DreamMetric.sm) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 13))
                .foregroundStyle(Color.dreamPrimary)
            Text("It's ok — come back tomorrow.")
                .font(.dreamGrotesk(13, .medium))
                .foregroundStyle(Color.dreamSubtle)
        }
        .padding(.top, -8)
    }

    // MARK: - Latest dream hero

    @ViewBuilder
    private var latestSection: some View {
        if let latest = dreams.first {
            NavigationLink {
                DreamDetailView(dream: latest)
            } label: {
                heroCard(latest)
            }
            .buttonStyle(PressableTileStyle())
        }
    }

    private func heroCard(_ dream: Dream) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow("▸ Latest dream", color: .dreamPrimary)
                .padding(.bottom, 12)

            Text(dream.title)
                .font(.dreamSerif(29))
                .foregroundStyle(Color.dreamText)
                .lineLimit(2)
                .padding(.trailing, 96)

            Text(dream.entry)
                .font(.dreamGrotesk(14))
                .foregroundStyle(Color.dreamSubtle)
                .lineSpacing(3)
                .lineLimit(3)
                .padding(.top, 14)

            Rectangle()
                .fill(Color.dreamText.opacity(0.08))
                .frame(height: 1)
                .padding(.top, 18)

            HStack(alignment: .top, spacing: 22) {
                metaColumn("Mood") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(dream.mood.tint)
                            .frame(width: 8, height: 8)
                            .shadow(color: dream.mood.tint.opacity(0.7), radius: 3)
                        Text(localized(dream.mood.rawValue))
                            .font(.dreamMono(11))
                            .foregroundStyle(Color.dreamText)
                    }
                }
                metaColumn("Recorded") {
                    Text(dream.date, format: .dateTime.hour().minute())
                        .font(.dreamMono(11))
                        .foregroundStyle(Color.dreamSubtle)
                }
                if dream.isPublic {
                    metaColumn("Shared") {
                        HStack(spacing: 5) {
                            Image(systemName: "globe")
                            Text("Feed")
                        }
                        .font(.dreamMono(11))
                        .foregroundStyle(Color.dreamPrimary)
                    }
                }
            }
            .padding(.top, 16)

            if !dream.tags.isEmpty {
                HStack(spacing: 16) {
                    ForEach(Array(dream.tags.prefix(3).enumerated()), id: \.element) { index, tag in
                        Text("· \(tag)")
                            .font(.dreamMono(11))
                            .foregroundStyle(tagTint(index))
                    }
                }
                .padding(.top, 16)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background { DreamCardFill(radius: DreamMetric.heroRadius) }
        .overlay(alignment: .topTrailing) {
            MoodOrb(tint: dream.mood.tint, diameter: 72)
                .padding(.top, 12)
                .padding(.trailing, 16)
        }
        .clipShape(RoundedRectangle(cornerRadius: DreamMetric.heroRadius))
        // Added after the clip so it isn't cut off: a duplicate of the card shape,
        // hidden behind the opaque fill, casts the shadow — blurring this flat
        // shape is far cheaper than blurring the whole finished card.
        .background {
            RoundedRectangle(cornerRadius: DreamMetric.heroRadius)
                .fill(Color.dreamSurface)
                .shadow(color: Color.dreamCardShadow.opacity(0.1), radius: 12, x: 0, y: 6)
        }
        .overlay(DreamCardRim(radius: DreamMetric.heroRadius))
        .overlay(alignment: .topTrailing) {
            StarGlintView()
                .offset(x: -28, y: -5.5)
        }
    }

    private func tagTint(_ index: Int) -> Color {
        [.dreamPrimary, .dreamAccent, .dreamSubtle][index % 3]
    }

    private func metaColumn<Value: View>(_ label: String, @ViewBuilder _ value: () -> Value) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Eyebrow(label, size: 9, tracking: 1.4)
            value()
        }
    }

    // MARK: - Stats (streak + total)

    private var statsRow: some View {
        HStack(spacing: 0) {
            statBlock(value: "\(streak.current)", label: "Night streak", color: .dreamPrimary, flameLit: streakRolling)
            Rectangle()
                .fill(Color.dreamText.opacity(0.08))
                .frame(width: 1, height: 46)
                .padding(.horizontal, 18)
            statBlock(value: "\(dreams.count)", label: "Dreams logged", color: .dreamText)
        }
        .padding(.horizontal, 22)
    }

    private func statBlock(value: String, label: String, color: Color, flameLit: Bool? = nil) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(value)
                    .font(.dreamSerif(38))
                    .foregroundStyle(color)
                if let flameLit {
                    StreakFlame(isLit: flameLit)
                }
            }
            Eyebrow(label, size: 9.5, tracking: 1.3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Week tracker

    /// The seven days of the current week (Mon→Sun), each flagged journaled /
    /// today, driven from the same set the streak uses.
    private var weekDays: [(letter: String, journaled: Bool, isToday: Bool)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let weekday = cal.component(.weekday, from: today) // 1=Sun … 7=Sat
        let daysFromMonday = (weekday + 5) % 7
        guard let monday = cal.date(byAdding: .day, value: -daysFromMonday, to: today) else { return [] }
        let letters = ["M", "T", "W", "T", "F", "S", "S"]
        return (0..<7).map { i in
            let day = cal.date(byAdding: .day, value: i, to: monday) ?? monday
            return (letters[i], journaledDays.contains(day), cal.isDate(day, inSameDayAs: today))
        }
    }

    private var weekJournaledCount: Int { weekDays.filter(\.journaled).count }

    private var weekTracker: some View {
        VStack(spacing: 12) {
            HStack {
                Eyebrow("This week", size: 9.5, tracking: 1.4)
                Spacer()
                Text("\(weekJournaledCount) of 7 nights")
                    .font(.dreamMono(9.5))
                    .tracking(0.4)
                    .foregroundStyle(Color.dreamSubtle)
            }
            HStack(spacing: 0) {
                ForEach(Array(weekDays.enumerated()), id: \.offset) { _, day in
                    VStack(spacing: 7) {
                        Circle()
                            .fill(day.journaled ? Color.dreamPrimary : Color.dreamText.opacity(0.14))
                            .frame(width: 11, height: 11)
                            .overlay {
                                if day.isToday {
                                    Circle().stroke(Color.dreamPrimary.opacity(0.22), lineWidth: 3)
                                        .padding(-3)
                                }
                            }
                        Text(day.letter)
                            .font(.dreamMono(9))
                            .foregroundStyle(day.isToday ? Color.dreamPrimary : Color.dreamFaint)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dreamCard(radius: DreamMetric.tileRadius)
    }

    // MARK: - Weekly quest preview

    /// The week's quests plus the stats they're measured against.
    private var weekQuests: (quests: [Quest], stats: QuestStats) {
        Quest.currentWeek(dreams: dreams, journaledDays: journaledDays)
    }

    /// A completed quest waiting to be claimed takes priority and shows a Claim
    /// card; otherwise the quest nearest completion links to the full list. Hidden
    /// when there's nothing to claim and nothing left in progress.
    @ViewBuilder
    private var questPreview: some View {
        let week = weekQuests
        if let quest = week.quests.first(where: {
            QuestRewards.isClaimable($0, stats: week.stats, weekStart: Quest.weekStart())
        }) {
            Button {
                claim(quest)
            } label: {
                claimableCard(quest)
            }
            .buttonStyle(PressableTileStyle())
        } else if let quest = Quest.closestIncomplete(in: week.quests, stats: week.stats) {
            Button {
                router.showQuests()
            } label: {
                questCard(quest, stats: week.stats)
            }
            .buttonStyle(PressableTileStyle())
        }
    }

    private func claimableCard(_ quest: Quest) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(quest.tint.opacity(0.9))
                    .frame(width: 40, height: 40)
                Image(systemName: "gift.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Eyebrow("Quest complete", color: quest.tint, size: 9.5, tracking: 1.4)
                Text(localized(quest.title))
                    .font(.dreamGrotesk(15, .semibold))
                    .foregroundStyle(Color.dreamText)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text("Claim +\(quest.xp)")
                .font(.dreamGrotesk(13, .bold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    LinearGradient(
                        colors: [quest.tint, quest.tint.opacity(0.75)],
                        startPoint: .leading, endPoint: .trailing
                    ),
                    in: .capsule
                )
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { DreamCardFill(radius: DreamMetric.tileRadius) }
        .overlay(DreamCardRim(radius: DreamMetric.tileRadius, tint: quest.tint))
        .shadow(color: quest.tint.opacity(0.25), radius: 10, y: 4)
    }

    private func questCard(_ quest: Quest, stats: QuestStats) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(quest.tint.opacity(0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: quest.symbol)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(quest.tint)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Eyebrow("Weekly quest", size: 9.5, tracking: 1.4)
                    Spacer()
                    Text("+\(quest.xp) XP")
                        .font(.dreamMono(10, .semibold))
                        .foregroundStyle(quest.tint)
                }
                Text(localized(quest.title))
                    .font(.dreamGrotesk(15, .semibold))
                    .foregroundStyle(Color.dreamText)
                    .lineLimit(1)
                HStack(spacing: 8) {
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
                        .font(.dreamMono(9.5))
                        .foregroundStyle(Color.dreamSubtle)
                        .lineLimit(1)
                        .fixedSize()
                }

                // What the quest actually asks for, below the progress bar.
                Text(localized(quest.detail))
                    .font(.dreamBody(11))
                    .foregroundStyle(Color.dreamSubtle)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.dreamText.opacity(0.4))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dreamCard(radius: DreamMetric.tileRadius)
    }

    /// Claim a completed quest's XP: bank it and fire the reward animation.
    private func claim(_ quest: Quest) {
        guard QuestRewards.isClaimable(quest, stats: weekQuests.stats, weekStart: Quest.weekStart()) else {
            return
        }
        questBankedXP = QuestRewards.claim(quest, weekStart: Quest.weekStart(), currentTotal: questBankedXP)
        router.presentClaim(xp: quest.xp, title: localized(quest.title))
        // Push the claim to the account right away so it survives a force-quit and
        // reaches other devices without waiting for sign-out / relaunch.
        Task { await auth.syncProgressState() }
    }

    // MARK: - Random dream tile ("wander back")

    private var randomDreamTile: some View {
        Button {
            // Re-roll each tap; never the dream already shown as the hero.
            randomDream = dreams.dropFirst().randomElement() ?? dreams.first
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Eyebrow("↻ Wander back", color: .dreamPrimary)
                    .padding(.bottom, 12)
                Text("Revisit a random dream")
                    .font(.dreamSerif(26))
                    .foregroundStyle(Color.dreamText)
                    .lineLimit(2)
                    .padding(.trailing, 92)
                Text("Let one of your \(dreams.count) nights find you again.")
                    .font(.dreamGrotesk(13))
                    .foregroundStyle(Color.dreamSubtle)
                    .lineSpacing(2)
                    .padding(.top, 8)
                    .padding(.trailing, 60)
                HStack(spacing: 9) {
                    Text("Surprise me")
                        .font(.dreamGrotesk(13, .semibold))
                        .foregroundStyle(Color.dreamOnCTA)
                    Text("→")
                        .font(.dreamGrotesk(15))
                        .foregroundStyle(Color.dreamCTAGlyph)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(Color.dreamCTAFill, in: .rect(cornerRadius: DreamMetric.pillRadius))
                .padding(.top, 18)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 22)
            .padding(.vertical, 24)
            .background { DreamCardFill(radius: DreamMetric.heroRadius) }
            .overlay(alignment: .topTrailing) {
                floatingOrbs
                    .padding(.top, -6)
                    .padding(.trailing, 2)
            }
            .clipShape(RoundedRectangle(cornerRadius: DreamMetric.heroRadius))
            .overlay(DreamCardRim(radius: DreamMetric.heroRadius))
        }
        .buttonStyle(PressableTileStyle())
    }

    private var floatingOrbs: some View {
        ZStack {
            MoodOrb(tint: Dream.Mood.vivid.tint, diameter: 46)
                .offset(x: -26, y: 10)
            MoodOrb(tint: Dream.Mood.strange.tint, diameter: 28, bloom: false)
                .offset(x: 2, y: 44)
                .opacity(0.85)
            MoodOrb(tint: Dream.Mood.peaceful.tint, diameter: 18, bloom: false)
                .offset(x: -48, y: 50)
                .opacity(0.7)
        }
        .frame(width: 120, height: 120)
    }

    // MARK: - Achievements

    /// Metrics every badge is evaluated against, mirroring the Progress screen.
    private var achievementStats: AchievementStats {
        AchievementStats(
            dreams: dreams,
            journaledDays: journaledDays,
            lucidSections: lucidSectionsCompleted
        )
    }

    /// The two most recently unlocked badges, surfaced as a Home highlight.
    private var recentAchievements: [Achievement] {
        AchievementTracker.recentlyUnlocked(for: achievementStats, limit: 2)
    }

    /// Recent achievements with a tap-through to the full gallery. Hidden until at
    /// least one badge is unlocked.
    @ViewBuilder
    private var achievementsSection: some View {
        if !recentAchievements.isEmpty {
            NavigationLink {
                AchievementsView(stats: achievementStats)
            } label: {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Eyebrow("Achievements", color: .dreamAccent)
                        Spacer()
                        Text("View all →")
                            .font(.dreamGrotesk(12, .semibold))
                            .foregroundStyle(Color.dreamPrimary)
                    }
                    ForEach(recentAchievements) { achievement in
                        achievementRow(achievement)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(22)
                .dreamCard(radius: DreamMetric.heroRadius)
            }
            .buttonStyle(PressableTileStyle())
        }
    }

    private func achievementRow(_ achievement: Achievement) -> some View {
        HStack(spacing: 14) {
            Image(systemName: achievement.symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(achievement.tint)
                .frame(width: 44, height: 44)
                .background(achievement.tint.opacity(0.16), in: .circle)

            VStack(alignment: .leading, spacing: 2) {
                Text(achievement.title)
                    .font(.dreamGrotesk(15, .semibold))
                    .foregroundStyle(Color.dreamText)
                Text(achievement.detail)
                    .font(.dreamGrotesk(12))
                    .foregroundStyle(Color.dreamSubtle)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: DreamMetric.sm) {
            Eyebrow("Nothing logged yet", color: .dreamPrimary)
            Text("Your first dream is waiting")
                .font(.dreamSerif(24))
                .foregroundStyle(Color.dreamText)
            Text("Tap “Capture tonight's dream” the moment you wake — before it fades.")
                .font(.dreamGrotesk(14))
                .foregroundStyle(Color.dreamSubtle)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .dreamCard(radius: DreamMetric.heroRadius, starred: true)
    }

    // MARK: - Stats helpers (streak)

    /// Days journaled — a dream recorded or marked "can't remember" — used to
    /// derive the streak and the week tracker.
    private var journaledDays: Set<Date> {
        let calendar = Calendar.current
        let dreamDays = dreams.map { calendar.startOfDay(for: $0.date) }
        return Set(dreamDays).union(store.skippedDays)
    }

    private var streak: Streak { Streak.from(journaledDays: journaledDays) }

    /// Whether the streak is currently alive — drives the lit flame.
    private var streakRolling: Bool { streak.current > 0 }

    // MARK: - Tips

    /// The account tip resolves once signed in.
    private var accountTipOutstanding: Bool { !auth.isSignedIn }
    /// The Lock Screen widget tip resolves once an accessory widget is installed.
    private var widgetTipOutstanding: Bool { !hasLockScreenWidget }

    /// Number of tips still to complete; drives the count badge.
    private var tipsRemaining: Int {
        (accountTipOutstanding ? 1 : 0) + (widgetTipOutstanding ? 1 : 0)
    }

    /// Ask WidgetKit whether any HalfLight Lock Screen (accessory) widget is
    /// installed; if so, the Lock Screen widget tip is complete.
    private func refreshLockScreenWidgetTip() {
        WidgetCenter.shared.getCurrentConfigurations { result in
            guard case .success(let widgets) = result else { return }
            let hasAccessory = widgets.contains { info in
                switch info.family {
                case .accessoryCircular, .accessoryRectangular, .accessoryInline: true
                default: false
                }
            }
            Task { @MainActor in hasLockScreenWidget = hasAccessory }
        }
    }

    /// The Tips section — hidden entirely once every tip is done.
    @ViewBuilder
    private var tipsSection: some View {
        if tipsRemaining > 0 {
            VStack(alignment: .leading, spacing: DreamMetric.md) {
                HStack(spacing: 8) {
                    Eyebrow("Tips", size: 9.5, tracking: 1.4)
                    Text("\(tipsRemaining)")
                        .font(.dreamMono(10, .semibold))
                        .foregroundStyle(Color.dreamOnPrimary)
                        .frame(width: 18, height: 18)
                        .background(Color.dreamPrimary, in: .circle)
                }

                if accountTipOutstanding {
                    TipCard(
                        icon: "icloud.fill",
                        title: "Create an account",
                        detail: "Back up your dreams to the cloud so they're saved and synced — you'll never lose a memory.",
                        action: { showAuth = true }
                    )
                }

                if widgetTipOutstanding {
                    TipCard(
                        icon: "lock.fill",
                        title: "Add a Lock Screen widget",
                        detail: "Put HalfLight on your Lock Screen to capture dreams the moment you wake, before they fade."
                    )
                }
            }
            .padding(.top, 4)
        }
    }
}

// MARK: - Reusable redesign components

/// The mono eyebrow label: uppercased, letter-spaced, recessive by default.
struct Eyebrow: View {
    let text: String
    var color: Color = .dreamFaint
    var size: CGFloat = 10
    var tracking: CGFloat = 1.7

    init(_ text: String, color: Color = .dreamFaint, size: CGFloat = 10, tracking: CGFloat = 1.7) {
        self.text = text
        self.color = color
        self.size = size
        self.tracking = tracking
    }

    var body: some View {
        Text(localized(text))
            .font(.dreamMono(size, .medium))
            .tracking(tracking)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}

/// The night-streak flame: a warm gradient flame that glows and gently pulses
/// while the streak is alive, and falls to a flat gray when it isn't.
struct StreakFlame: View {
    let isLit: Bool

    private var flameGradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: 0xFFD86B), Color(hex: 0xF5A02E), Color(hex: 0xE0552A)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    var body: some View {
        Image(systemName: "flame.fill")
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(
                isLit ? AnyShapeStyle(flameGradient)
                      : AnyShapeStyle(Color.dreamText.opacity(0.18))
            )
            .shadow(color: isLit ? Color(hex: 0xF5A02E).opacity(0.55) : .clear,
                    radius: isLit ? 8 : 0)
            .symbolEffect(.pulse, options: .repeating, isActive: isLit)
            .accessibilityLabel(isLit ? "Streak active" : "Streak inactive")
    }
}

/// The split-circle brand mark: half brand accent, half recessive — a literal
/// "half light".
struct BrandMark: View {
    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: .dreamPrimary, location: 0.5),
                        .init(color: .dreamText.opacity(0.22), location: 0.5)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: 13, height: 13)
            .shadow(color: Color.dreamPrimary.opacity(0.4), radius: 5)
    }
}

/// The signature glowing orb in a dream's mood color — a lit 3D sphere with a
/// soft outer bloom. `Color = mood` is the core of the visual language.
struct MoodOrb: View {
    let tint: Color
    var diameter: CGFloat = 96
    var bloom: Bool = true

    var body: some View {
        ZStack {
            if bloom {
                // The radial fall-off alone reads as the bloom — the `.blur` that
                // used to sit on top was a live Gaussian pass per orb (one per
                // feed card) that cost real frame time while barely changing an
                // already-soft gradient.
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [tint.opacity(0.38), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: diameter * 0.75
                        )
                    )
                    .frame(width: diameter * 1.5, height: diameter * 1.5)
            }

            Circle()
                .fill(tint)
                .overlay(
                    // Top-left specular highlight reads as a light source.
                    Circle().fill(
                        RadialGradient(
                            colors: [.white.opacity(0.55), .clear],
                            center: UnitPoint(x: 0.36, y: 0.32),
                            startRadius: 0,
                            endRadius: diameter * 0.5
                        )
                    )
                )
                .overlay(
                    // Lower-right core shading for roundness.
                    Circle().fill(
                        RadialGradient(
                            colors: [.clear, .black.opacity(0.26)],
                            center: UnitPoint(x: 0.7, y: 0.82),
                            startRadius: diameter * 0.1,
                            endRadius: diameter * 0.62
                        )
                    )
                )
                .frame(width: diameter, height: diameter)
                .shadow(color: tint.opacity(0.45), radius: diameter * 0.16)
        }
        .frame(width: diameter, height: diameter)
    }
}

/// An informational tip on the Home dashboard.
private struct TipCard: View {
    let icon: String
    let title: String
    let detail: String
    var action: (() -> Void)? = nil

    var body: some View {
        if let action {
            Button(action: action) { card }
                .buttonStyle(PressableTileStyle())
        } else {
            card
        }
    }

    private var card: some View {
        HStack(alignment: .top, spacing: DreamMetric.md) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.dreamPrimary)
                .frame(width: 40, height: 40)
                .background(Color.dreamPrimary.opacity(0.12), in: .circle)

            VStack(alignment: .leading, spacing: DreamMetric.xs) {
                Text(title)
                    .font(.dreamCardTitle)
                    .foregroundStyle(Color.dreamText)
                Text(detail)
                    .font(.dreamSubtext)
                    .foregroundStyle(Color.dreamSubtle)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if action != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.dreamText.opacity(0.4))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DreamMetric.lg)
        .dreamCard(radius: DreamMetric.tileRadius)
    }
}

#Preview("Light") {
    HomeView()
        .modelContainer(PreviewData.container)
        .environment(PreviewData.store)
        .environment(AuthService())
        .environment(AppRouter())
        .environment(SubscriptionManager())
}

#Preview("Dark") {
    HomeView()
        .modelContainer(PreviewData.container)
        .environment(PreviewData.store)
        .environment(AuthService())
        .environment(AppRouter())
        .environment(SubscriptionManager())
        .preferredColorScheme(.dark)
}
