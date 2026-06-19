//
//  ProfileView.swift
//  HalfLight
//
//  The Profile tab: the dreamer's name, account status, and a way into
//  Settings. (Leaderboard / friends will live here later.)
//

import SwiftUI
import SwiftData

struct ProfileView: View {
    @Environment(AuthService.self) private var auth
    @Query private var dreams: [Dream]
    @AppStorage("userName") private var userName = "Dreamer"
    @State private var showAuth = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    accountCard
                    themesCard
                }
                .padding(20)
            }
            .tabBarClearance()
            .background { DreamBackground() }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showAuth) {
                AuthView()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(userName)
                    .font(.dreamDisplay(28))
                Text(auth.isSignedIn ? (auth.email ?? "Signed in") : "Not signed in")
                    .font(.dreamBody(13, .medium))
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
    }

    // MARK: - Top themes

    /// Every theme, ranked highest-count first.
    private var rankedThemes: [(name: String, count: Int)] {
        rankedDreamThemes(from: dreams)
    }

    /// The five most-repeated themes.
    private var topThemes: [(name: String, count: Int)] {
        Array(rankedThemes.prefix(5))
    }

    private var themesCard: some View {
        VStack(alignment: .leading, spacing: DreamMetric.md) {
            HStack(spacing: DreamMetric.sm) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.dreamPrimary)
                Text("Top themes")
                    .font(.dreamDisplay(20, .bold))
            }

            if topThemes.isEmpty {
                Text("Journal dreams to see your top themes.")
                    .font(.dreamBody(14))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(topThemes.enumerated()), id: \.element.name) { index, theme in
                    NavigationLink {
                        ThemeDreamsView(theme: theme.name)
                    } label: {
                        ThemeRow(rank: index + 1, name: theme.name, count: theme.count)
                    }
                    .buttonStyle(.plain)
                }

                if rankedThemes.count > topThemes.count {
                    NavigationLink {
                        AllThemesView()
                    } label: {
                        HStack {
                            Text("See all themes")
                                .font(.dreamBody(14, .semibold))
                                .foregroundStyle(Color.dreamPrimary)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.dreamPrimary)
                        }
                        .padding(.top, DreamMetric.xs)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DreamMetric.lg)
        .dreamCard()
    }

    @ViewBuilder
    private var accountCard: some View {
        if auth.isSignedIn {
            HStack(spacing: DreamMetric.md) {
                Image(systemName: "checkmark.icloud.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.dreamPrimary)
                    .frame(width: 44, height: 44)
                    .background(Color.dreamPrimary.opacity(0.12), in: .circle)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Account active")
                        .font(.dreamDisplay(16, .bold))
                    Text(auth.email ?? "Your dreams are backed up")
                        .font(.dreamBody(13))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DreamMetric.lg)
            .dreamCard()
        } else {
            Button {
                showAuth = true
            } label: {
                HStack(spacing: DreamMetric.md) {
                    Image(systemName: "icloud.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.dreamPrimary)
                        .frame(width: 44, height: 44)
                        .background(Color.dreamPrimary.opacity(0.12), in: .circle)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Create an account")
                            .font(.dreamDisplay(16, .bold))
                        Text("Back up and sync your dreams")
                            .font(.dreamBody(13))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

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
    }
}

/// Tags across the given dreams, deduped case-insensitively and counted once per
/// dream, ranked by frequency (ties broken alphabetically). Used by both the
/// Profile top-5 list and the full list.
func rankedDreamThemes(from dreams: [Dream]) -> [(name: String, count: Int)] {
    var counts: [String: (name: String, count: Int)] = [:]
    for dream in dreams {
        var seen = Set<String>()
        for raw in dream.tags {
            let tag = raw.trimmingCharacters(in: .whitespaces)
            let key = tag.lowercased()
            guard !tag.isEmpty, seen.insert(key).inserted else { continue }
            if let existing = counts[key] {
                counts[key] = (existing.name, existing.count + 1)
            } else {
                counts[key] = (tag, 1)
            }
        }
    }
    return counts.values
        .sorted {
            $0.count != $1.count
                ? $0.count > $1.count
                : $0.name.lowercased() < $1.name.lowercased()
        }
        .map { ($0.name, $0.count) }
}

/// One ranked theme row: rank badge, name, count, and a chevron.
struct ThemeRow: View {
    let rank: Int
    let name: String
    let count: Int

    var body: some View {
        HStack(spacing: DreamMetric.md) {
            Text("\(rank)")
                .font(.dreamBody(13, .bold))
                .foregroundStyle(Color.dreamPrimary)
                .frame(width: 24, height: 24)
                .background(Color.dreamPrimary.opacity(0.12), in: .circle)

            Text(name)
                .font(.dreamBody(15, .medium))

            Spacer(minLength: 0)

            Text("\(count) \(count == 1 ? "dream" : "dreams")")
                .font(.dreamBody(12, .semibold))
                .foregroundStyle(.secondary)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.dreamText.opacity(0.4))
        }
    }
}

/// The full ranked list of themes, reached via "See all themes" on the Profile.
/// Searchable by theme name; rows keep their overall rank while filtering.
struct AllThemesView: View {
    @Query private var dreams: [Dream]
    @State private var query = ""

    /// Themes matching the search, each carrying its overall (unfiltered) rank.
    private var rows: [(rank: Int, name: String, count: Int)] {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        return rankedDreamThemes(from: dreams).enumerated().compactMap { index, theme in
            guard trimmed.isEmpty || theme.name.lowercased().contains(trimmed) else { return nil }
            return (index + 1, theme.name, theme.count)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: DreamMetric.md) {
                if rows.isEmpty {
                    Text("No themes match “\(query)”.")
                        .font(.dreamBody(14))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else {
                    ForEach(rows, id: \.name) { row in
                        NavigationLink {
                            ThemeDreamsView(theme: row.name)
                        } label: {
                            ThemeRow(rank: row.rank, name: row.name, count: row.count)
                                .padding(DreamMetric.lg)
                                .dreamCard()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(20)
        }
        .tabBarClearance()
        .background { DreamBackground() }
        .searchable(text: $query, prompt: "Search themes")
        .navigationTitle("All themes")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

/// All dreams that carry a given theme (tag), reached by tapping a theme on the
/// Profile screen. Filtering is done in memory (case-insensitive) since SwiftData
/// predicates don't match across a stored `[String]` cleanly.
struct ThemeDreamsView: View {
    let theme: String

    @Query(sort: \Dream.date, order: .reverse) private var dreams: [Dream]

    private var matching: [Dream] {
        dreams.filter { dream in
            dream.tags.contains { $0.caseInsensitiveCompare(theme) == .orderedSame }
        }
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
        .navigationTitle(theme)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

#Preview("Light") {
    ProfileView()
        .modelContainer(PreviewData.container)
        .environment(AuthService())
}

#Preview("Dark") {
    ProfileView()
        .modelContainer(PreviewData.container)
        .environment(AuthService())
        .preferredColorScheme(.dark)
}
