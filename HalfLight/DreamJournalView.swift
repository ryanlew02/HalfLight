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

                if !dreams.isEmpty {
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
                    } else if filteredDreams.isEmpty {
                        noResults
                    } else {
                        library
                    }
                }
            }
            .background { DreamBackground() }
            .toolbar(.hidden, for: .navigationBar)
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
                sortMenu
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
                Text(label)
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
                    Text(dream.mood.rawValue)
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
        .background(Color.dreamSurface, in: .rect(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(dream.mood.tint.opacity(0.25), lineWidth: 1)
        )
    }
}

#Preview("Light") {
    DreamJournalView()
        .modelContainer(PreviewData.container)
        .environment(PreviewData.store)
}

#Preview("Dark") {
    DreamJournalView()
        .modelContainer(PreviewData.container)
        .environment(PreviewData.store)
        .preferredColorScheme(.dark)
}
