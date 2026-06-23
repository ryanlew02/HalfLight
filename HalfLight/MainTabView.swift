//
//  MainTabView.swift
//  HalfLight
//
//  Root shell: hosts the selected screen and the bottom tab bar, and owns the
//  global "add dream" sheet triggered by the center "+".
//

import SwiftUI
import SwiftData

struct MainTabView: View {
    @Environment(DreamStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Query private var dreams: [Dream]
    @AppStorage("lucidSectionsCompleted") private var lucidSectionsCompleted = 0
    @AppStorage("questBankedXP") private var questBankedXP = 0
    /// The highest level already celebrated, so each level-up fires its popup once.
    /// `0` means "not yet seeded" — set on first appear so existing dreamers don't
    /// get a level-up screen just for launching the app.
    @AppStorage("celebratedLevel") private var celebratedLevel = 0
    @AppStorage("dailyReminderEnabled") private var reminderEnabled = false
    /// Morning reminder time, stored as minutes since midnight (default 9:00 AM).
    @AppStorage("morningReminderMinutes") private var morningReminderMinutes = 9 * 60

    @State private var router = AppRouter()
    @State private var tabBarHeight: CGFloat = 0

    var body: some View {
        @Bindable var router = router
        ZStack {
            currentScreen
                .id(router.tab)
                .transition(.opacity)
        }
            .foregroundStyle(Color.dreamText)
            .environment(\.tabBarHeight, tabBarHeight)
            .environment(router)
            .safeAreaInset(edge: .bottom) {
                CustomTabBar(selection: $router.tab)
                    .measuresTabBarHeight()
            }
            .onPreferenceChange(TabBarHeightPreferenceKey.self) { tabBarHeight = $0 }
            .overlay {
                if let reward = router.claimReward {
                    Group {
                        switch reward.kind {
                        case .xp:
                            XPClaimView(reward: reward) { router.dismissClaim() }
                        case .levelUp:
                            LevelUpView(reward: reward) { router.dismissClaim() }
                        }
                    }
                    .transition(.opacity)
                    .zIndex(10)
                }
            }
            // Morning quick-capture: opened from a widget / Control / Siri, this
            // sheet starts a new dream with dictation already running, from any tab.
            .fullScreenCover(isPresented: $router.quickRecord) {
                AddDreamView(autoDictate: true) { draft in
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
            // Record the baseline of already-earned badges once, then celebrate any
            // achievement the moment the dreamer crosses its goal — from any source.
            .task {
                AchievementTracker.seedIfNeeded(for: achievementStats)
                // Seed the level baseline once so we only celebrate future level-ups.
                if celebratedLevel == 0 { celebratedLevel = currentLevel }
                refreshReminders()
                updateWidgetSnapshot()
                consumeQuickRecordRequest()
            }
            .onChange(of: unlockedAchievementCount) { _, _ in
                let newly = AchievementTracker.newlyUnlocked(for: achievementStats)
                if !newly.isEmpty { router.presentAchievements(newly) }
            }
            // Any XP source (a logged dream, a lucid lesson, a quest, an achievement)
            // can push the dreamer over a level threshold — celebrate it from here.
            .onChange(of: currentLevel) { _, newLevel in
                guard celebratedLevel != 0, newLevel > celebratedLevel else { return }
                let rank = DreamProgression.rank(forLevel: newLevel)
                router.presentLevelUp(level: newLevel, rank: rank.name)
                celebratedLevel = newLevel
            }
            // Keep reminders in step with usage: app foreground, journaling activity,
            // and the setting itself all reschedule the morning / inactivity / streak nudges.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    refreshReminders()
                    updateWidgetSnapshot()
                    consumeQuickRecordRequest()
                }
            }
            .onChange(of: dreams.count) { _, _ in refreshReminders(); updateWidgetSnapshot() }
            .onChange(of: store.skippedDays) { _, _ in refreshReminders(); updateWidgetSnapshot() }
            .onChange(of: reminderEnabled) { _, _ in refreshReminders() }
            .onChange(of: morningReminderMinutes) { _, _ in refreshReminders() }
    }

    // MARK: - Widgets & quick capture

    /// Refresh the shared snapshot the home-screen and lock-screen widgets read.
    private func updateWidgetSnapshot() {
        WidgetSnapshotWriter.update(dreams: dreams, journaledDays: journaledDays)
    }

    /// Honor a pending widget / Control / Siri "record a dream" request by opening
    /// the quick-capture sheet. The signal is one-shot and freshness-gated.
    private func consumeQuickRecordRequest() {
        if QuickRecordSignal.consume() { router.quickRecord = true }
    }

    /// Whether today has already banked its once-per-day journaling XP, so the
    /// quick-capture reward popup fires only when XP is genuinely earned. Mirrors
    /// the same check in `DreamJournalView`.
    private var hasJournalXPToday: Bool {
        let today = Calendar.current.startOfDay(for: .now)
        if dreams.contains(where: { Calendar.current.isDateInToday($0.date) }) { return true }
        return store.skippedDays.contains(today) || store.creditedDays.contains(today)
    }

    // MARK: - Reminders

    private var journaledDays: Set<Date> {
        let calendar = Calendar.current
        return Set(dreams.map { calendar.startOfDay(for: $0.date) })
            .union(store.skippedDays)
    }

    private func refreshReminders() {
        // Snapshot state on the main actor before hopping to the async scheduler.
        let days = journaledDays
        let enabled = reminderEnabled
        let journaledToday = days.contains(Calendar.current.startOfDay(for: .now))
        let streak = Streak.from(journaledDays: days).current
        let morningMinutes = morningReminderMinutes
        Task {
            let ok = await ReminderScheduler.shared.refresh(
                enabled: enabled,
                journaledToday: journaledToday,
                currentStreak: streak,
                morningHour: morningMinutes / 60,
                morningMinute: morningMinutes % 60
            )
            // Permission denied — keep the setting honest by switching it back off.
            if enabled && !ok { reminderEnabled = false }
        }
    }

    // MARK: - Level tracking

    /// Total XP via the shared `DreamStore.totalXP`, so level-ups fire at exactly
    /// the thresholds the Progress and Profile screens show.
    private var totalXP: Int {
        store.totalXP(
            dreams: dreams,
            lucidSections: lucidSectionsCompleted,
            questBankedXP: questBankedXP
        )
    }

    private var currentLevel: Int { DreamProgression.level(forXP: totalXP) }

    /// Metrics every badge is evaluated against, rebuilt from the live library.
    /// Mirrors the achievement stats the Progress screen shows so unlocks line up.
    private var achievementStats: AchievementStats {
        AchievementStats(
            dreams: dreams,
            journaledDays: journaledDays,
            lucidSections: lucidSectionsCompleted
        )
    }

    /// How many badges are currently unlocked. Watched by `onChange` as the trigger
    /// for the achievement popups — it climbs whenever a new badge is earned.
    private var unlockedAchievementCount: Int {
        Achievement.all.reduce(0) { $0 + ($1.isUnlocked(for: achievementStats) ? 1 : 0) }
    }

    @ViewBuilder
    private var currentScreen: some View {
        switch router.tab {
        case .home: HomeView()
        case .lucid: LucidDreamView()
        case .journal: DreamJournalView()
        case .feed: FeedView()
        case .profile: ProfileView()
        }
    }
}

#Preview("Light") {
    MainTabView()
        .modelContainer(PreviewData.container)
        .environment(PreviewData.store)
        .environment(AuthService())
        .environment(SubscriptionManager())
}

#Preview("Dark") {
    MainTabView()
        .modelContainer(PreviewData.container)
        .environment(PreviewData.store)
        .environment(AuthService())
        .environment(SubscriptionManager())
        .preferredColorScheme(.dark)
}

