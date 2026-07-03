//
//  DreamJournalView.swift
//  HalfLight
//
//  The dream library: a scrollable list of recorded dreams.
//

import SwiftUI
import SwiftData

struct DreamJournalView: View {
    @Query(sort: \Dream.date, order: .reverse) private var dreams: [Dream]
    @Environment(DreamStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var isAddingDream = false
    /// The dream being edited via the long-press menu, presented in `AddDreamView`.
    @State private var editingDream: Dream?
    @State private var searchText = ""
    @State private var sortOption: SortOption = .newest
    /// Moods the dreamer is filtering to. Empty means "all moods".
    @State private var selectedMoods: Set<Dream.Mood> = []
    /// When on, search matches by meaning too — related words (synonyms) and
    /// whole-sentence semantic similarity. Persisted so the preference sticks.
    @AppStorage("journalSmartMatch") private var smartMatch = true
    /// Whether the library renders as the scrolling list or the month calendar.
    /// Persisted so the journal reopens the way the dreamer left it.
    @AppStorage("journalViewMode") private var viewMode: ViewMode = .list

    /// The two ways of browsing the library.
    enum ViewMode: String {
        case list, calendar
    }

    /// The month the calendar is showing (first of the month). Opens on the
    /// present; the arrows and the month/year wheels move it.
    @State private var displayedMonth =
        Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
    /// Whether the month/year wheels are expanded under the calendar header.
    @State private var showingMonthPicker = false
    /// Caches a semantic vector per dream for "search by vibe" ranking.
    @State private var semanticIndex = DreamSemanticIndex()

    /// Similarity below this counts as no semantic match (sentence embeddings give
    /// moderate scores even for unrelated text, so we need a floor).
    private static let semanticThreshold = 0.30
    /// How strongly semantic similarity feeds the relevance score. Kept below the
    /// weight of a literal hit so exact matches always rank first.
    private static let semanticWeight = 8.0

    /// How the library is ordered. The default mirrors the old fixed query (newest
    /// first); the rest let the dreamer re-sort in place.
    enum SortOption: String, CaseIterable, Identifiable {
        case newest, oldest, title, mood

        var id: String { rawValue }

        var label: String {
            switch self {
            case .newest: "Newest first"
            case .oldest: "Oldest first"
            case .title: "Title (A–Z)"
            case .mood: "Mood"
            }
        }

        var systemImage: String {
            switch self {
            case .newest: "arrow.down"
            case .oldest: "arrow.up"
            case .title: "textformat"
            case .mood: "face.smiling"
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 12)

                // Search and mood filters only apply to the list; the calendar
                // always shows the whole library.
                if !dreams.isEmpty && viewMode == .list {
                    searchBar
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)

                    if availableMoods.count > 1 {
                        moodFilterRow
                            .padding(.bottom, 12)
                    }
                }

                Group {
                    if dreams.isEmpty {
                        emptyState
                    } else if viewMode == .calendar {
                        calendarView
                    } else if filteredDreams.isEmpty {
                        noResults
                    } else {
                        library
                    }
                }
            }
            .background { DreamBackground() }
            .toolbar(.hidden, for: .navigationBar)
            .keyboardDoneToolbar()
            // Keep the semantic index in step with the library (adds/edits/deletes).
            .task(id: dreamsSignature) {
                semanticIndex.prune(keeping: dreams)
                semanticIndex.index(dreams)
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
            .fullScreenCover(item: $editingDream) { dream in
                AddDreamView(existingDream: dream) { draft in
                    store.update(dream, with: draft)
                } onDelete: {
                    store.delete(dream)
                }
            }
        }
    }

    /// Whether today has already banked its once-per-day journaling XP — via a
    /// recorded dream, a "can't remember" skip, or a credit left by a deleted
    /// dream. Used to fire the reward popup only when XP is genuinely earned.
    private var hasJournalXPToday: Bool {
        let today = Calendar.current.startOfDay(for: .now)
        if dreams.contains(where: { Calendar.current.isDateInToday($0.date) }) { return true }
        return store.skippedDays.contains(today) || store.creditedDays.contains(today)
    }

    /// Changes whenever a dream is added, edited, or removed — drives re-indexing.
    private var dreamsSignature: Int {
        var hasher = Hasher()
        hasher.combine(dreams.count)
        for dream in dreams { hasher.combine(dream.updatedAt) }
        return hasher.finalize()
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Text("Journal")
                .font(.dreamTitle)
            Spacer()
            if !dreams.isEmpty {
                viewModeButton
                if viewMode == .list {
                    sortMenu
                }
            }
            Button {
                SoundManager.shared.play(.tap)
                isAddingDream = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.dreamPrimary)
            }
            .accessibilityLabel("Add Dream")
        }
    }

    // MARK: - Search & sort

    /// Dreams after the active search filter and chosen sort are applied. While
    /// searching, results come back in best-match order (smart word + synonym
    /// matching); otherwise the chosen sort option is honored.
    private var filteredDreams: [Dream] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let searching = !query.isEmpty

        var matched: [Dream]
        if searching {
            // Touch `version` so results re-rank once background indexing lands.
            _ = semanticIndex.version
            let queryVector = smartMatch ? DreamSearch.sentenceVector(for: query) : nil

            matched = dreams
                .compactMap { dream -> (dream: Dream, score: Double)? in
                    var score = DreamSearch.score(
                        for: dream,
                        query: query,
                        includeSynonyms: smartMatch
                    )
                    // Blend in whole-sentence semantic similarity ("vibe" match).
                    if let queryVector, let dreamVector = semanticIndex.vector(for: dream) {
                        let similarity = DreamSearch.cosineSimilarity(queryVector, dreamVector)
                        if similarity > Self.semanticThreshold {
                            score += (similarity - Self.semanticThreshold) * Self.semanticWeight
                        }
                    }
                    return score > 0 ? (dream, score) : nil
                }
                .sorted { $0.score == $1.score ? $0.dream.date > $1.dream.date : $0.score > $1.score }
                .map(\.dream)
        } else {
            matched = dreams
        }

        if !selectedMoods.isEmpty {
            matched = matched.filter { selectedMoods.contains($0.mood) }
        }

        // Relevance order already sorts search results; only re-sort when browsing.
        return searching ? matched : sortedByOption(matched)
    }

    private func sortedByOption(_ dreams: [Dream]) -> [Dream] {
        switch sortOption {
        case .newest:
            dreams.sorted { $0.date > $1.date }
        case .oldest:
            dreams.sorted { $0.date < $1.date }
        case .title:
            dreams.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .mood:
            // Group by mood, newest first within each group.
            dreams.sorted {
                $0.mood.rawValue == $1.mood.rawValue
                    ? $0.date > $1.date
                    : $0.mood.rawValue < $1.mood.rawValue
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search dreams, moods, tags…", text: $searchText)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .font(.dreamBody(15))
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.dreamSurface, in: .rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.dreamText.opacity(0.08), lineWidth: 1)
        )
    }

    /// Flips the library between the list and the month calendar. Sits next to
    /// the sort menu and borrows its circular treatment.
    private var viewModeButton: some View {
        Button {
            SoundManager.shared.play(.tap)
            viewMode = viewMode == .list ? .calendar : .list
        } label: {
            Image(systemName: viewMode == .list ? "calendar" : "list.bullet")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.dreamPrimary)
                .frame(width: 32, height: 32)
                .background(Color.dreamPrimary.opacity(0.12), in: .circle)
        }
        .accessibilityLabel(viewMode == .list ? "Show calendar" : "Show list")
    }

    private var sortMenu: some View {
        Menu {
            Section("Search") {
                Toggle(isOn: $smartMatch) {
                    Label("Match by meaning", systemImage: "wand.and.stars")
                }
            }
            Picker("Sort by", selection: $sortOption) {
                ForEach(SortOption.allCases) { option in
                    Label(option.label, systemImage: option.systemImage).tag(option)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.dreamPrimary)
                .frame(width: 32, height: 32)
                .background(Color.dreamPrimary.opacity(0.12), in: .circle)
        }
        .accessibilityLabel("Sort dreams")
    }

    // MARK: - Mood filter

    /// Moods that actually appear in the library, in the canonical mood order, so
    /// the chip row only offers filters that would return something.
    private var availableMoods: [Dream.Mood] {
        let present = Set(dreams.map(\.mood))
        return Dream.Mood.allCases.filter { present.contains($0) }
    }

    private var moodFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                moodChip(
                    label: "All",
                    symbol: "circle.grid.2x2",
                    tint: .dreamPrimary,
                    isSelected: selectedMoods.isEmpty
                ) {
                    selectedMoods.removeAll()
                }

                ForEach(availableMoods) { mood in
                    moodChip(
                        label: mood.rawValue,
                        symbol: mood.symbol,
                        tint: mood.tint,
                        isSelected: selectedMoods.contains(mood)
                    ) {
                        toggle(mood)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func moodChip(
        label: String,
        symbol: String,
        tint: Color,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            SoundManager.shared.play(.tap)
            action()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                Text(localized(label))
                    .font(.dreamBody(13, .semibold))
            }
            .foregroundStyle(isSelected ? .white : tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isSelected ? tint : tint.opacity(0.14), in: .capsule)
            .overlay(
                Capsule().stroke(tint.opacity(isSelected ? 0 : 0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    private func toggle(_ mood: Dream.Mood) {
        if selectedMoods.contains(mood) {
            selectedMoods.remove(mood)
        } else {
            selectedMoods.insert(mood)
        }
    }

    // MARK: - No search results

    private var noResults: some View {
        ContentUnavailableView {
            Label("No Matches", systemImage: "magnifyingglass")
        } description: {
            Text(noResultsMessage)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noResultsMessage: String {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return "No dreams match “\(trimmed)”."
        }
        return "No dreams in the moods you've selected."
    }

    // MARK: - Calendar

    /// Every day (start-of-day) that has at least one journaled dream — drives
    /// the dots and which days tap through to their dreams.
    private var dreamDays: Set<Date> {
        let cal = Calendar.current
        return Set(dreams.map { cal.startOfDay(for: $0.date) })
    }

    /// The first day of the earliest journaled dream's month — the calendar
    /// can't page back past this.
    private var firstCalendarMonth: Date {
        let cal = Calendar.current
        let earliest = dreams.map(\.date).min() ?? .now
        return cal.dateInterval(of: .month, for: earliest)?.start ?? earliest
    }

    /// The first day of the latest month the calendar can page to — this month,
    /// or a stray future-dated dream's month if one exists.
    private var lastCalendarMonth: Date {
        let cal = Calendar.current
        let latest = max(.now, dreams.map(\.date).max() ?? .now)
        return cal.dateInterval(of: .month, for: latest)?.start ?? latest
    }

    private func clampedToCalendarRange(_ month: Date) -> Date {
        min(max(month, firstCalendarMonth), lastCalendarMonth)
    }

    private func stepMonth(by delta: Int) {
        guard let next = Calendar.current.date(
            byAdding: .month, value: delta, to: displayedMonth
        ) else { return }
        displayedMonth = clampedToCalendarRange(next)
    }

    private var calendarView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DreamMetric.md) {
                monthNavigator

                if showingMonthPicker {
                    monthYearPicker
                }

                MonthCalendarGrid(
                    monthStart: clampedToCalendarRange(displayedMonth),
                    dreamDays: dreamDays
                )
            }
            .padding(DreamMetric.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dreamCard()
            .padding(.horizontal, 20)
            .padding(.top, 4)
        }
        .tabBarClearance()
    }

    /// The calendar's header: arrows stepping a month at a time, with the month
    /// title between them. Tapping the title toggles the month/year wheels.
    private var monthNavigator: some View {
        HStack {
            monthArrow(
                systemImage: "chevron.left",
                disabled: displayedMonth <= firstCalendarMonth,
                accessibilityLabel: "Previous month"
            ) {
                stepMonth(by: -1)
            }

            Spacer(minLength: 0)

            Button {
                SoundManager.shared.play(.tap)
                withAnimation(.easeInOut(duration: 0.2)) {
                    showingMonthPicker.toggle()
                }
            } label: {
                HStack(spacing: 5) {
                    Text(displayedMonth.formatted(.dateTime.month(.wide).year()))
                        .font(.dreamBody(16, .semibold))
                        .foregroundStyle(Color.dreamText)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.dreamPrimary)
                        .rotationEffect(.degrees(showingMonthPicker ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Choose month and year")

            Spacer(minLength: 0)

            monthArrow(
                systemImage: "chevron.right",
                disabled: displayedMonth >= lastCalendarMonth,
                accessibilityLabel: "Next month"
            ) {
                stepMonth(by: 1)
            }
        }
    }

    private func monthArrow(
        systemImage: String,
        disabled: Bool,
        accessibilityLabel: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            SoundManager.shared.play(.tap)
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(disabled ? Color.dreamText.opacity(0.25) : Color.dreamPrimary)
                .frame(width: 32, height: 32)
                .background(
                    Color.dreamPrimary.opacity(disabled ? 0.05 : 0.12),
                    in: .circle
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(accessibilityLabel)
    }

    /// Side-by-side month and year wheels for jumping straight to a month,
    /// revealed by tapping the navigator's title. Selections outside the
    /// journal's span clamp back to the nearest covered month.
    private var monthYearPicker: some View {
        HStack(spacing: 0) {
            Picker("Month", selection: displayedMonthComponentBinding(.month)) {
                ForEach(1...12, id: \.self) { month in
                    // Months outside the journal's span (older than the first
                    // dream, or still in the future) stay listed so the wheel
                    // doesn't reshuffle, but read clearly muted — picking one
                    // clamps to the nearest covered month.
                    Text(Calendar.current.standaloneMonthSymbols[month - 1])
                        .foregroundStyle(
                            isMonthPickable(month)
                                ? Color.dreamText
                                : Color.dreamText.opacity(0.25)
                        )
                        .tag(month)
                }
            }
            Picker("Year", selection: displayedMonthComponentBinding(.year)) {
                ForEach(calendarYears, id: \.self) { year in
                    // Verbatim so the year renders without a grouping separator.
                    Text(verbatim: "\(year)").tag(year)
                }
            }
        }
        #if os(iOS)
        .pickerStyle(.wheel)
        #endif
        .frame(height: 130)
    }

    /// Whether the given month, in the year the wheel currently shows, falls
    /// inside the journal's span — drives the muted look of unpickable months.
    private func isMonthPickable(_ month: Int) -> Bool {
        let cal = Calendar.current
        var parts = cal.dateComponents([.year], from: displayedMonth)
        parts.month = month
        parts.day = 1
        guard let candidate = cal.date(from: parts) else { return false }
        return candidate >= firstCalendarMonth && candidate <= lastCalendarMonth
    }

    /// Every year the journal spans, for the year wheel.
    private var calendarYears: [Int] {
        let cal = Calendar.current
        let first = cal.component(.year, from: firstCalendarMonth)
        let last = cal.component(.year, from: lastCalendarMonth)
        return Array(first...last)
    }

    /// A binding onto the displayed month's `.month` or `.year` component;
    /// setting it rebuilds the date and clamps it into the journal's span.
    private func displayedMonthComponentBinding(_ component: Calendar.Component) -> Binding<Int> {
        Binding(
            get: { Calendar.current.component(component, from: displayedMonth) },
            set: { newValue in
                let cal = Calendar.current
                var parts = cal.dateComponents([.year, .month], from: displayedMonth)
                switch component {
                case .month: parts.month = newValue
                case .year: parts.year = newValue
                default: return
                }
                parts.day = 1
                guard let picked = cal.date(from: parts) else { return }
                displayedMonth = clampedToCalendarRange(picked)
            }
        )
    }

    // MARK: - Library

    private var library: some View {
        List {
            ForEach(filteredDreams) { dream in
                // The NavigationLink is hidden behind the card so the List doesn't
                // draw its trailing disclosure chevron; the whole row still taps
                // through to the detail view.
                ZStack {
                    NavigationLink {
                        DreamDetailView(dream: dream)
                    } label: {
                        EmptyView()
                    }
                    .opacity(0)

                    DreamCard(dream: dream)
                }
                .contextMenu {
                    Button {
                        SoundManager.shared.play(.tap)
                        editingDream = dream
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        store.delete(dream)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            .onDelete { offsets in
                let visible = filteredDreams
                for index in offsets {
                    store.delete(visible[index])
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .tabBarClearance()
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Dreams Yet", systemImage: "moon.stars")
        } description: {
            Text("Capture your first dream before it fades.")
        } actions: {
            Button {
                SoundManager.shared.play(.tap)
                isAddingDream = true
            } label: {
                Text("Add a Dream")
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
        }
    }
}

/// A single dream rendered as a card in the library.
struct DreamCard: View {
    let dream: Dream

    var body: some View {
        VStack(alignment: .leading, spacing: DreamMetric.sm) {
            HStack {
                Label {
                    Text(localized(dream.mood.rawValue))
                        .font(.dreamCaption)
                } icon: {
                    Image(systemName: dream.mood.symbol)
                }
                .foregroundStyle(dream.mood.tint)

                Spacer()

                if dream.isPublic {
                    Image(systemName: "globe")
                        .font(.dreamBody(12, .semibold))
                        .foregroundStyle(Color.dreamPrimary)
                        .accessibilityLabel("Shared to feed")
                }

                Text(dream.date, format: .dateTime.month().day().hour().minute())
                    .font(.dreamBody(12, .medium))
                    .foregroundStyle(.secondary)
            }

            Text(dream.title)
                .font(.dreamCardTitle)
                .lineLimit(2)

            Text(dream.entry)
                .font(.dreamSubtext)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .lineLimit(3)

            if !dream.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DreamMetric.sm) {
                        ForEach(dream.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.dreamBody(12, .semibold))
                                .padding(.horizontal, DreamMetric.md)
                                .padding(.vertical, DreamMetric.xs)
                                .background(dream.mood.tint.opacity(0.18), in: .capsule)
                                .foregroundStyle(dream.mood.tint)
                        }
                    }
                }
            }
        }
        .padding(DreamMetric.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        // The shared half-lit card surface, same as every other screen. The
        // mood's color still reads from the label and tag capsules.
        .dreamCard()
    }
}

/// One month of the journal calendar: a locale-aware weekday header and the day
/// grid. Days with a journaled dream carry a dot and tap through to that day's
/// dreams; today reads in the accent color. The title and card surface live in
/// the journal's month navigator, which pages this grid month by month.
private struct MonthCalendarGrid: View {
    let monthStart: Date
    /// Start-of-day dates that have at least one dream.
    let dreamDays: Set<Date>

    private let calendar = Calendar.current
    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 0),
        count: 7
    )

    var body: some View {
        VStack(alignment: .leading, spacing: DreamMetric.md) {
            LazyVGrid(columns: columns, spacing: DreamMetric.xs) {
                ForEach(weekdaySymbols.indices, id: \.self) { index in
                    Text(weekdaySymbols[index])
                        .font(.dreamBody(11, .semibold))
                        .foregroundStyle(.secondary)
                }

                ForEach(Array(dayCells.enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day)
                    } else {
                        // Leading blank before the month's first weekday.
                        Color.clear.frame(height: 36)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Single-letter weekday labels, rotated so the row starts on the locale's
    /// first weekday (Sunday in the US, Monday most elsewhere).
    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        return Array(symbols[shift...]) + Array(symbols[..<shift])
    }

    /// The month's days padded with `nil` blanks so day 1 lands on its weekday.
    private var dayCells: [Date?] {
        guard let dayRange = calendar.range(of: .day, in: .month, for: monthStart) else {
            return []
        }
        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let leadingBlanks = (firstWeekday - calendar.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: leadingBlanks)
        for day in dayRange {
            cells.append(calendar.date(byAdding: .day, value: day - 1, to: monthStart))
        }
        return cells
    }

    @ViewBuilder
    private func dayCell(_ day: Date) -> some View {
        let hasDream = dreamDays.contains(day)
        let isToday = calendar.isDateInToday(day)
        let label = VStack(spacing: 3) {
            Text("\(calendar.component(.day, from: day))")
                .font(.dreamBody(13, isToday || hasDream ? .semibold : .regular).monospacedDigit())
                .foregroundStyle(
                    isToday
                        ? Color.dreamPrimary
                        : Color.dreamText.opacity(hasDream ? 1 : 0.45)
                )
            Circle()
                .fill(hasDream ? Color.dreamPrimary : .clear)
                .frame(width: 5, height: 5)
        }
        .frame(maxWidth: .infinity, minHeight: 36)
        .contentShape(Rectangle())

        if hasDream {
            NavigationLink {
                DayDreamsView(day: day)
            } label: {
                label
            }
            .buttonStyle(.plain)
        } else {
            label
        }
    }
}

/// The dreams journaled on a single day, reached by tapping a dotted day on the
/// journal calendar.
struct DayDreamsView: View {
    /// The day's start-of-day date.
    let day: Date

    @Query(sort: \Dream.date, order: .reverse) private var dreams: [Dream]

    private var matching: [Dream] {
        dreams.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(matching) { dream in
                    NavigationLink {
                        DreamDetailView(dream: dream)
                    } label: {
                        DreamCard(dream: dream)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
        }
        .tabBarClearance()
        .background { DreamBackground() }
        .navigationTitle(day.formatted(date: .abbreviated, time: .omitted))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

#Preview("Light") {
    DreamJournalView()
        .modelContainer(PreviewData.container)
        .environment(PreviewData.store)
        .environment(SubscriptionManager())
}

#Preview("Dark") {
    DreamJournalView()
        .modelContainer(PreviewData.container)
        .environment(PreviewData.store)
        .environment(SubscriptionManager())
        .preferredColorScheme(.dark)
}
