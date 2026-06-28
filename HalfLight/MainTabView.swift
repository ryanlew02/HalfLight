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
    @Environment(AuthService.self) private var auth
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
    /// Tabs the dreamer has opened at least once. Their screens stay built and are
    /// just shown/hidden, so returning to a tab is instant instead of a cold reload.
    @State private var visitedTabs: Set<AppTab> = []
    /// Covers startup with the dreamy launch screen while every tab is built behind
    /// it, so the app reveals with all screens ready (no first-open lag).
    @State private var isWarmingUp = true
    /// True for the brief window after a sign-in while the account's dreams, XP and
    /// achievements stream in. Celebrations are folded silently into the baseline
    /// during this window, so signing in doesn't unleash a backlog of level-up and
    /// achievement popups for progress that was already earned on the account.
    @State private var isRestoringAccount = false

    var body: some View {
        @Bindable var router = router
        @Bindable var store = store
        tabHost
            .foregroundStyle(Color.dreamText)
            // Surface a daily rate-limit rejection (publishing, commenting,
            // reporting) from anywhere in the app, then clear it.
            .alert(
                "Daily limit reached",
                isPresented: Binding(
                    get: { store.rateLimitNotice != nil },
                    set: { if !$0 { store.rateLimitNotice = nil } }
                ),
                presenting: store.rateLimitNotice
            ) { _ in
                Button("OK", role: .cancel) { store.rateLimitNotice = nil }
            } message: { notice in
                Text(notice)
            }
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
                // Build the (static) lesson curriculum off the main thread now, so the
                // first open of the Lucid tab doesn't pay that one-time cost on-screen.
                Task.detached(priority: .utility) { _ = LucidCurriculum.sections }
                // Build every tab behind the launch screen, then reveal the app.
                await warmUpAndReveal()
            }
            .onChange(of: unlockedAchievementCount) { _, _ in
                // While an account is restoring, fold the incoming badges into the
                // baseline silently instead of celebrating each one.
                if isRestoringAccount {
                    AchievementTracker.markAllCelebrated(for: achievementStats)
                    return
                }
                let newly = AchievementTracker.newlyUnlocked(for: achievementStats)
                if !newly.isEmpty { router.presentAchievements(newly) }
            }
            // Any XP source (a logged dream, a lucid lesson, a quest, an achievement)
            // can push the dreamer over a level threshold — celebrate it from here.
            .onChange(of: currentLevel) { _, newLevel in
                // Account restore: advance the baseline without a level-up screen.
                if isRestoringAccount { celebratedLevel = newLevel; return }
                guard celebratedLevel != 0, newLevel > celebratedLevel else { return }
                let rank = DreamProgression.rank(forLevel: newLevel)
                router.presentLevelUp(level: newLevel, rank: localized(rank.name))
                celebratedLevel = newLevel
            }
            // A sign-in pulls the account's dreams/XP/achievements in over the next
            // moments; suppress celebrations for that surge and re-baseline once it
            // has settled, so only progress earned afterwards is celebrated.
            .onChange(of: auth.status) { _, status in
                guard status == .signedIn else { return }
                isRestoringAccount = true
                Task {
                    try? await Task.sleep(for: .seconds(4))
                    celebratedLevel = currentLevel
                    AchievementTracker.markAllCelebrated(for: achievementStats)
                    isRestoringAccount = false
                }
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
            // Topmost layer: the dreamy launch screen, shown until warm-up finishes.
            .overlay {
                if isWarmingUp {
                    LaunchLoadingView()
                        .transition(.opacity)
                        .zIndex(100)
                }
            }
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

    /// Hosts every visited tab in one stack, showing only the selected one. A tab's
    /// screen isn't built until first opened (lazy), then kept alive — so switching
    /// back is an opacity flip rather than a full rebuild + re-run of its `.task`.
    private var tabHost: some View {
        ZStack {
            ForEach(AppTab.allCases) { tab in
                if visitedTabs.contains(tab) {
                    screen(for: tab)
                        .opacity(router.tab == tab ? 1 : 0)
                        // Instant switch (no crossfade): the outgoing screen is hidden
                        // the same frame, so a pushed screen being reset on tab change
                        // (e.g. Profile's Progress) never shows a close animation.
                        .allowsHitTesting(router.tab == tab)
                        .accessibilityHidden(router.tab != tab)
                        .zIndex(router.tab == tab ? 1 : 0)
                }
            }
        }
        .onChange(of: router.tab, initial: true) { _, tab in
            visitedTabs.insert(tab)
        }
    }

    /// Build every tab behind the launch screen, then fade the launch screen out so
    /// the app reveals with all screens already constructed — making the first tap on
    /// each one instant. Each tab is marked visited in turn (the keep-alive host then
    /// builds it), staggered so no single build stalls a frame, and the dreamy screen
    /// is held a graceful minimum so it doesn't just blink past on a fast device.
    private func warmUpAndReveal() async {
        let start = Date()
        // Spin up the tap sound's audio engine now so the first tab tap is instant.
        SoundManager.shared.warmUp()
        for tab in AppTab.allCases where !visitedTabs.contains(tab) {
            visitedTabs.insert(tab)
            try? await Task.sleep(for: .milliseconds(160))
        }
        // Hold the launch screen for a minimum so it reads as intentional, not a flash.
        let minimum: TimeInterval = 1.7
        let elapsed = Date().timeIntervalSince(start)
        if elapsed < minimum {
            try? await Task.sleep(for: .seconds(minimum - elapsed))
        }
        withAnimation(.easeInOut(duration: 0.6)) { isWarmingUp = false }
    }

    @ViewBuilder
    private func screen(for tab: AppTab) -> some View {
        switch tab {
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

