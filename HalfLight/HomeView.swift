//
//  HomeView.swift
//  HalfLight
//
//  Landing dashboard: a quick summary and the most recent dream.
//

import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(DreamStore.self) private var store
    @Query(sort: \Dream.date, order: .reverse) private var dreams: [Dream]

    /// The day (start-of-day, as a time interval) the user last tapped "I'm not sure".
    /// Used to keep the prompt dismissed for the rest of that day.
    @AppStorage("dreamPromptSkippedDay") private var skippedDay: Double = 0
    @State private var isAddingDream = false
    /// Drives the brief "come back tomorrow" confirmation shown right after the
    /// user taps "I'm not sure". Auto-hides after a couple of seconds.
    @State private var showSkippedMessage = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    greeting
                    if showTodayPrompt {
                        todayPrompt
                    } else if showSkippedMessage {
                        skippedMessage
                    }
                    summary
                    latest
                }
                .padding(20)
            }
            .background { DreamBackground() }
            .fullScreenCover(isPresented: $isAddingDream) {
                AddDreamView { draft in
                    store.add(draft)
                }
            }
        }
    }

    private var greeting: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Welcome back!")
                    .font(.largeTitle.weight(.bold))
                Text("Capture your dreams before they fade.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            NavigationLink {
                SettingsView()
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.title2)
                    .foregroundStyle(Color.dreamPrimary)
            }
            .accessibilityLabel("Settings")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.dreamPrimary)
                Text("Did you dream last night?")
                    .font(.headline)
            }

            Text("Capture it now before the details slip away.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button {
                    isAddingDream = true
                } label: {
                    Text("Record a dream")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.dreamPrimary, in: .rect(cornerRadius: 12))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Button {
                    skippedDay = Calendar.current.startOfDay(for: .now).timeIntervalSince1970
                    SkippedDayStore.record(.now)
                    withAnimation { showSkippedMessage = true }
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        withAnimation { showSkippedMessage = false }
                    }
                } label: {
                    Text("I'm not sure")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.dreamSurface, in: .rect(cornerRadius: 12))
                        .foregroundStyle(Color.dreamText)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.dreamText.opacity(0.12), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.dreamSurface, in: .rect(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.dreamPrimary.opacity(0.25), lineWidth: 1)
        )
    }

    private var skippedMessage: some View {
        HStack(spacing: 10) {
            Image(systemName: "moon.zzz.fill")
                .foregroundStyle(Color.dreamPrimary)
            Text("It's ok — come back tomorrow!")
                .font(.subheadline.weight(.medium))
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.dreamSurface, in: .rect(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.dreamPrimary.opacity(0.25), lineWidth: 1)
        )
    }

    private var summary: some View {
        HStack(spacing: 12) {
            SummaryCard(value: "\(dreams.count)", label: "Total dreams", icon: "book.fill")
            SummaryCard(value: "\(weekCount)", label: "This week", icon: "calendar")
        }
    }

    @ViewBuilder
    private var latest: some View {
        if let latest = dreams.first {
            VStack(alignment: .leading, spacing: 10) {
                Text("Latest dream")
                    .font(.headline)
                NavigationLink {
                    DreamDetailView(dream: latest)
                } label: {
                    DreamCard(dream: latest)
                }
                .buttonStyle(.plain)
            }
        } else {
            Text("No dreams yet - tap the + below to record your first.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
        }
    }

    private var weekCount: Int {
        let weekAgo = Date.now.addingTimeInterval(-7 * 24 * 60 * 60)
        return dreams.filter { $0.date >= weekAgo }.count
    }
}

/// A compact stat tile used on the Home dashboard.
private struct SummaryCard: View {
    let value: String
    let label: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(Color.dreamPrimary)
            Text(value)
                .font(.title.weight(.bold))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.dreamSurface, in: .rect(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.dreamText.opacity(0.08), lineWidth: 1)
        )
    }
}

#Preview("Light") {
    HomeView()
        .modelContainer(PreviewData.container)
        .environment(PreviewData.store)
}

#Preview("Dark") {
    HomeView()
        .modelContainer(PreviewData.container)
        .environment(PreviewData.store)
        .preferredColorScheme(.dark)
}
