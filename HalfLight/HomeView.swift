//
//  HomeView.swift
//  HalfLight
//
//  Landing dashboard. The latest dream is the emotional focal point (a hero
//  card lit by its mood color); the today-prompt nudges logging, and the stat
//  tiles are deliberately demoted beneath it.
//

import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(DreamStore.self) private var store
    @Environment(AuthService.self) private var auth
    @Query(sort: \Dream.date, order: .reverse) private var dreams: [Dream]

    /// The day (start-of-day, as a time interval) the user last tapped "I'm not sure".
    /// Used to keep the prompt dismissed for the rest of that day.
    @AppStorage("userName") private var userName = "Dreamer"
    @AppStorage("dreamPromptSkippedDay") private var skippedDay: Double = 0
    @State private var isAddingDream = false
    /// Drives the brief "come back tomorrow" confirmation shown right after the
    /// user taps "I'm not sure". Auto-hides after a couple of seconds.
    @State private var showSkippedMessage = false
    /// The dream picked by "Revisit a random dream"; setting it pushes the detail view.
    @State private var randomDream: Dream?
    /// Set right after a new dream is saved; pushes its detail view so the user
    /// can immediately analyze it with AI.
    @State private var newDream: Dream?
    /// Presents the account sheet from the "Create an account" tip.
    @State private var showAuth = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DreamMetric.xxl) {
                    greeting
                    if showTodayPrompt {
                        todayPrompt
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    } else if showSkippedMessage {
                        skippedMessage
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    latestSection
                    if dreams.count >= 2 {
                        randomDreamButton
                    }
                    summary
                    tipsSection
                }
                .padding(.horizontal, DreamMetric.screen)
                .padding(.top, DreamMetric.sm)
                .padding(.bottom, DreamMetric.xl)
            }
            .tabBarClearance()
            .background { NightSkyBackground() }
            .navigationDestination(item: $randomDream) { dream in
                DreamDetailView(dream: dream)
            }
            .navigationDestination(item: $newDream) { dream in
                DreamDetailView(dream: dream)
            }
            .sheet(isPresented: $showAuth) {
                AuthView()
            }
            .fullScreenCover(isPresented: $isAddingDream) {
                AddDreamView { draft in
                    newDream = store.add(draft)
                }
            }
        }
    }

    // MARK: - Greeting

    private var greetingText: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        case 17..<22: "Good evening"
        default: "Good night"
        }
    }

    private var greeting: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: DreamMetric.xs) {
                Text("\(greetingText), \(userName)")
                    .font(.dreamLargeTitle)
                Text(Date.now, format: .dateTime.weekday(.wide).month(.wide).day())
                    .font(.dreamBody(15, .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                isAddingDream = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.dreamPrimary)
            }
            .accessibilityLabel("Add Dream")
        }
    }

    // MARK: - Today's dream prompt

    /// Whether to nudge the user to log today's dream: only when they haven't
    /// recorded one today and haven't dismissed the prompt earlier today.
    private var showTodayPrompt: Bool {
        !hasDreamToday && !skippedToday
    }

    private var hasDreamToday: Bool {
        dreams.contains { Calendar.current.isDateInToday($0.date) }
    }

    private var skippedToday: Bool {
        guard skippedDay > 0 else { return false }
        return Calendar.current.isDateInToday(Date(timeIntervalSince1970: skippedDay))
    }

    private var todayPrompt: some View {
        VStack(alignment: .leading, spacing: DreamMetric.md) {
            HStack(spacing: DreamMetric.sm) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.dreamPrimary)
                Text("Did you dream last night?")
                    .font(.dreamDisplay(18, .bold))
            }

            Text("Capture it now before the details slip away.")
                .font(.dreamBodyText)
                .foregroundStyle(.secondary)

            HStack(spacing: DreamMetric.md) {
                Button("Record a dream") {
                    isAddingDream = true
                }
                .buttonStyle(PrimaryButtonStyle())

                Button("I'm not sure") {
                    skippedDay = Calendar.current.startOfDay(for: .now).timeIntervalSince1970
                    store.recordSkippedDay()
                    withAnimation { showSkippedMessage = true }
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        withAnimation { showSkippedMessage = false }
                    }
                }
                .buttonStyle(GhostButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DreamMetric.lg)
        .dreamCard()
    }

    private var skippedMessage: some View {
        HStack(spacing: DreamMetric.md) {
            Image(systemName: "moon.zzz.fill")
                .foregroundStyle(Color.dreamPrimary)
            Text("It's ok — come back tomorrow!")
                .font(.dreamDisplay(15, .bold))
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DreamMetric.lg)
        .dreamCard()
    }

    // MARK: - Latest dream (hero) + empty state

    @ViewBuilder
    private var latestSection: some View {
        if let latest = dreams.first {
            VStack(alignment: .leading, spacing: DreamMetric.md) {
                Text("Latest dream")
                    .font(.dreamSectionHeader)
                NavigationLink {
                    DreamDetailView(dream: latest)
                } label: {
                    HeroDreamCard(dream: latest)
                }
                .buttonStyle(.plain)
            }
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        VStack(spacing: DreamMetric.md) {
            Image(systemName: "moon.stars")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(Color.dreamPrimary.opacity(0.7))
            Text("No dreams yet")
                .font(.dreamSectionHeader)
            Text("Tap the + below to record your first — before it fades.")
                .font(.dreamBodyText)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DreamMetric.xxl)
    }

    // MARK: - Rediscover a random dream

    private var randomDreamButton: some View {
        Button {
            // Reselect each tap; never the dream already shown as the hero.
            randomDream = dreams.dropFirst().randomElement() ?? dreams.first
        } label: {
            HStack(spacing: DreamMetric.md) {
                Image(systemName: "shuffle")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.dreamPrimary)
                    .frame(width: 44, height: 44)
                    .background(Color.dreamPrimary.opacity(0.12), in: .circle)

                VStack(alignment: .leading, spacing: DreamMetric.xs) {
                    Text("Revisit a random dream")
                        .font(.dreamCardTitle)
                    Text("Rediscover a memory from your journal")
                        .font(.dreamSubtext)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.dreamText.opacity(0.4))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DreamMetric.lg)
            .dreamCard()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Stats (demoted)

    private var summary: some View {
        HStack(spacing: DreamMetric.md) {
            SummaryCard(value: "\(streak.current)", label: "Day streak", icon: "flame.fill", isLit: isStreakLit)
            SummaryCard(value: "\(dreams.count)", label: "Total dreams", icon: "book.fill")
            SummaryCard(value: "\(weekCount)", label: "This week", icon: "calendar")
        }
    }

    private var weekCount: Int {
        let weekAgo = Date.now.addingTimeInterval(-7 * 24 * 60 * 60)
        return dreams.filter { $0.date >= weekAgo }.count
    }

    /// Days journaled — a dream recorded or marked "can't remember" — used to
    /// derive the streak. Mirrors the set the Stats activity grid is built from.
    private var journaledDays: Set<Date> {
        let calendar = Calendar.current
        let dreamDays = dreams.map { calendar.startOfDay(for: $0.date) }
        return Set(dreamDays).union(store.skippedDays)
    }

    private var streak: Streak { Streak.from(journaledDays: journaledDays) }

    /// The streak card lights up once today is handled — a dream recorded *or*
    /// marked "can't remember", which count the same toward the streak — and the
    /// run is live. A small reward for keeping the chain going.
    private var isStreakLit: Bool {
        streak.current > 0 && journaledDays.contains(Calendar.current.startOfDay(for: .now))
    }

    // MARK: - Tips

    /// Outstanding tips: the account tip resolves once signed in; the widget tip
    /// is always available for now.
    private var tipsRemaining: Int { (auth.isSignedIn ? 0 : 1) + 1 }

    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: DreamMetric.md) {
            HStack(spacing: DreamMetric.sm) {
                Text("Tips")
                    .font(.dreamSectionHeader)
                Text("\(tipsRemaining)")
                    .font(.dreamDisplay(13, .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Color.dreamPrimary, in: .circle)
            }

            if !auth.isSignedIn {
                TipCard(
                    icon: "icloud.fill",
                    title: "Create an account",
                    detail: "Back up your dreams to the cloud so they're saved and synced — you'll never lose a memory.",
                    action: { showAuth = true }
                )
            }

            TipCard(
                icon: "lock.fill",
                title: "Add a Lock Screen widget",
                detail: "Put HalfLight on your Lock Screen to capture dreams the moment you wake, before they fade."
            )
        }
    }
}

/// An informational tip on the Home dashboard, explaining a way to get more
/// out of the app.
private struct TipCard: View {
    let icon: String
    let title: String
    let detail: String
    var isComplete: Bool = false
    var action: (() -> Void)? = nil

    var body: some View {
        if let action {
            Button(action: action) { card }
                .buttonStyle(.plain)
        } else {
            card
        }
    }

    private var card: some View {
        HStack(alignment: .top, spacing: DreamMetric.md) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.dreamPrimary)
                .frame(width: 44, height: 44)
                .background(Color.dreamPrimary.opacity(0.12), in: .circle)

            VStack(alignment: .leading, spacing: DreamMetric.xs) {
                Text(title)
                    .font(.dreamCardTitle)
                Text(detail)
                    .font(.dreamSubtext)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if isComplete {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.dreamPrimary)
            } else if action != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.dreamText.opacity(0.4))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DreamMetric.lg)
        .dreamCard()
    }
}

/// The latest dream, given visual primacy: large rounded title, mood-tinted
/// glow, and generous padding so it reads as the screen's centerpiece.
private struct HeroDreamCard: View {
    let dream: Dream

    var body: some View {
        VStack(alignment: .leading, spacing: DreamMetric.md) {
            HStack {
                Label {
                    Text(dream.mood.rawValue)
                        .font(.dreamBody(13, .semibold))
                } icon: {
                    Image(systemName: dream.mood.symbol)
                }
                .foregroundStyle(dream.mood.tint)

                Spacer()

                Text(dream.date, format: .dateTime.month().day().hour().minute())
                    .font(.dreamBody(12, .medium))
                    .foregroundStyle(.secondary)
            }

            Text(dream.title)
                .font(.dreamLargeTitle)
                .lineLimit(2)

            Text(dream.entry)
                .font(.dreamBodyText)
                .foregroundStyle(.secondary)
                .lineSpacing(4)
                .lineLimit(3)

            if !dream.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DreamMetric.sm) {
                        ForEach(dream.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.dreamBody(12, .semibold))
                                .padding(.horizontal, DreamMetric.md)
                                .padding(.vertical, DreamMetric.xs + 2)
                                .background(dream.mood.tint.opacity(0.18), in: .capsule)
                                .foregroundStyle(dream.mood.tint)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DreamMetric.xl)
        .dreamCard(glow: dream.mood.tint)
    }
}

/// A compact stat tile used on the Home dashboard. Deliberately quiet so it
/// sits beneath the hero dream rather than competing with it.
private struct SummaryCard: View {
    let value: String
    let label: String
    let icon: String
    /// When true the card glows and warms its icon/value — used to celebrate a
    /// live streak the moment today's dream is logged.
    var isLit = false

    var body: some View {
        VStack(alignment: .leading, spacing: DreamMetric.sm) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: isLit ? .bold : .medium))
                .foregroundStyle(isLit ? Color.dreamPrimary : Color.dreamText.opacity(0.5))
            Text(value)
                .font(.dreamDisplay(22, .bold))
                .foregroundStyle(isLit ? Color.dreamPrimary : Color.dreamText)
            Text(label)
                .font(.dreamBody(12, .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DreamMetric.lg)
        .dreamCard(glow: isLit ? .dreamPrimary : nil)
    }
}

#Preview("Light") {
    HomeView()
        .modelContainer(PreviewData.container)
        .environment(PreviewData.store)
        .environment(AuthService())
}

#Preview("Dark") {
    HomeView()
        .modelContainer(PreviewData.container)
        .environment(PreviewData.store)
        .environment(AuthService())
        .preferredColorScheme(.dark)
}
