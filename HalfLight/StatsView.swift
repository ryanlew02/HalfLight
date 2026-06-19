//
//  StatsView.swift
//  HalfLight
//
//  Simple insights computed from the dream library.
//

import SwiftUI
import SwiftData

struct StatsView: View {
    @Query private var dreams: [Dream]

    /// The calendar year shown in the activity grid; defaults to this year.
    @State private var selectedYear = Calendar.current.component(.year, from: .now)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text("Progress")
                        .font(.dreamDisplay(22))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    progressSection
                    if dreams.isEmpty {
                        emptyHint
                    } else {
                        activitySection
                        moodSection
                        tagSection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
            .tabBarClearance()
            .background { DreamBackground() }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: - Progress (XP & level)

    /// The lucid count is a placeholder until lucid progress is persisted.
    @AppStorage("lucidSectionsCompleted") private var lucidSectionsCompleted = 0
    private var totalXP: Int {
        DreamProgression.totalXP(journalEntries: dreams.count, lucidSections: lucidSectionsCompleted)
    }
    private var level: Int { DreamProgression.level(forXP: totalXP) }
    private var xpIntoLevel: Int { DreamProgression.xpIntoLevel(forXP: totalXP) }
    private var levelProgress: Double { DreamProgression.progress(forXP: totalXP) }
    private var rank: DreamProgression.Rank { DreamProgression.rank(forLevel: level) }

    private var progressSection: some View {
        NavigationLink {
            LevelsView(totalXP: totalXP)
        } label: {
            VStack(alignment: .leading, spacing: DreamMetric.md) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rank.name)
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

                Text("\(xpIntoLevel) / \(DreamProgression.xpPerLevel) XP to Level \(level + 1)")
                    .font(.dreamBody(12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DreamMetric.lg)
            .dreamCard()
        }
        .buttonStyle(.plain)
    }

    private var emptyHint: some View {
        Text("Record a few dreams to unlock your activity, moods, and themes.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Activity (past year)

    /// Side length of each day square, in points.
    private let squareSize: CGFloat = 11
    private let squareSpacing: CGFloat = 3

    private var activitySection: some View {
        let weeks = weeks(for: selectedYear)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                yearArrow(systemName: "chevron.left", enabled: selectedYear > earliestYear) {
                    selectedYear -= 1
                }

                Text(String(selectedYear))
                    .font(.headline)
                    .monospacedDigit()

                yearArrow(systemName: "chevron.right", enabled: selectedYear < currentYear) {
                    selectedYear += 1
                }

                Spacer()

                Text("\(daysJournaledCount(for: selectedYear)) days journaled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: squareSpacing) {
                        ForEach(Array(weeks.enumerated()), id: \.offset) { index, week in
                            VStack(spacing: squareSpacing) {
                                ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                                    daySquare(for: day)
                                }
                            }
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
                .font(.headline)
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

    private func daySquare(for day: Date?) -> some View {
        let isJournaled = day.map { journaledDays.contains($0) } ?? false
        return RoundedRectangle(cornerRadius: 2)
            .fill(isJournaled ? Color.dreamPrimary : Color.clear)
            .frame(width: squareSize, height: squareSize)
            .overlay {
                // Empty real days get a faint outline so the grid stays legible;
                // padding cells (nil) stay fully blank.
                if let day, !journaledDays.contains(day) {
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(Color.dreamText.opacity(0.12), lineWidth: 1)
                }
            }
    }

    // MARK: - Moods

    private var moodSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Moods")
                .font(.headline)
            ForEach(moodCounts, id: \.mood) { item in
                HStack(spacing: 12) {
                    Label(item.mood.rawValue, systemImage: item.mood.symbol)
                        .font(.subheadline)
                        .foregroundStyle(item.mood.tint)
                        .frame(width: 130, alignment: .leading)

                    GeometryReader { geo in
                        Capsule()
                            .fill(item.mood.tint.opacity(0.3))
                            .frame(width: barWidth(for: item.count, in: geo.size.width))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 14)

                    Text("\(item.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 28, alignment: .trailing)
                }
            }
        }
    }

    // MARK: - Tags

    @ViewBuilder
    private var tagSection: some View {
        if !topTags.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Top themes")
                    .font(.headline)
                ForEach(topTags, id: \.tag) { item in
                    HStack {
                        Text(item.tag)
                        Spacer()
                        Text("\(item.count)")
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }
            }
        }
    }

    // MARK: - Computed data

    /// Calendar days that count as journaled: a dream was recorded, or the user
    /// tapped "I'm not sure" on the home prompt. Normalized to start-of-day.
    private var journaledDays: Set<Date> {
        let calendar = Calendar.current
        let dreamDays = dreams.map { calendar.startOfDay(for: $0.date) }
        return Set(dreamDays).union(SkippedDayStore.days())
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

    private func daysJournaledCount(for year: Int) -> Int {
        let calendar = Calendar.current
        return journaledDays.filter { calendar.component(.year, from: $0) == year }.count
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

    private var moodCounts: [(mood: Dream.Mood, count: Int)] {
        Dream.Mood.allCases.map { mood in
            (mood, dreams.filter { $0.mood == mood }.count)
        }
    }

    private var topTags: [(tag: String, count: Int)] {
        let counts = Dictionary(grouping: dreams.flatMap(\.tags), by: { $0 })
            .mapValues(\.count)
        return counts
            .sorted { $0.value > $1.value }
            .prefix(8)
            .map { (tag: $0.key, count: $0.value) }
    }

    private func barWidth(for count: Int, in fullWidth: CGFloat) -> CGFloat {
        let maxCount = moodCounts.map(\.count).max() ?? 0
        guard maxCount > 0, count > 0 else { return 0 }
        let fraction = CGFloat(count) / CGFloat(maxCount)
        return max(8, fullWidth * fraction)
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
    StatsView()
        .modelContainer(PreviewData.container)
        .environment(PreviewData.store)
}

#Preview("Dark") {
    StatsView()
        .modelContainer(PreviewData.container)
        .environment(PreviewData.store)
        .preferredColorScheme(.dark)
}
