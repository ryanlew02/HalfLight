//
//  FeedSearchView.swift
//  HalfLight
//
//  Search across the feed, opened from the magnifying glass on the Feed header.
//  Two tabs: Accounts (dreamers, by @handle or name — via the `search_profiles`
//  RPC) and Posts (shared dreams, by title or text — a direct `feed_posts` query).
//  Presented as a sheet with its own navigation stack so a tapped account opens
//  their public profile and a tapped post opens a read-only detail.
//

import SwiftUI
import SwiftData

struct FeedSearchView: View {
    @Environment(AuthService.self) private var auth
    @Environment(DreamStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// Everyone the signed-in dreamer follows, so account rows show the right state.
    @Query private var follows: [Follow]

    enum Scope: Hashable { case accounts, posts }

    @State private var query = ""
    @State private var scope: Scope = .accounts
    @State private var accounts: [FollowProfile] = []
    @State private var posts: [FeedPostRecord] = []
    /// Post authors' avatars by lowercased @handle (posts carry no photo of their
    /// own), fetched after each search like the feed does.
    @State private var postAvatars: [String: Data] = [:]
    @State private var isSearching = false
    /// The last query actually searched, so an empty state only shows after a
    /// search has run — not before the first keystroke.
    @State private var searchedQuery: String?
    /// The in-flight debounce, cancelled on each keystroke.
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var searchFocused: Bool

    private var followedHandles: Set<String> {
        Set(follows.map { $0.username.lowercased() })
    }

    private var myHandle: String {
        (auth.username ?? UserDefaults.standard.string(forKey: "userUsername") ?? "")
            .lowercased()
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether the currently-shown tab has no results.
    private var currentIsEmpty: Bool {
        scope == .accounts ? accounts.isEmpty : posts.isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: DreamMetric.md) {
                searchBar
                scopePicker
                results
            }
            .padding(.top, DreamMetric.md)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background { DreamBackground() }
            .navigationTitle("Search")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear { searchFocused = true }
        .onChange(of: query) { _, newValue in scheduleSearch(newValue) }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: DreamMetric.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search dreamers and dreams", text: $query)
                .focused($searchFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .foregroundStyle(Color.dreamText)
            if !query.isEmpty {
                Button {
                    query = ""
                    searchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .font(.dreamBody(16))
        .padding(.horizontal, DreamMetric.md)
        .padding(.vertical, 10)
        .background(Color.dreamText.opacity(0.06), in: .capsule)
        .overlay(Capsule().strokeBorder(Color.dreamText.opacity(0.10), lineWidth: 1))
        .padding(.horizontal, DreamMetric.screen)
    }

    private var scopePicker: some View {
        Picker("Search scope", selection: $scope) {
            Text("Accounts").tag(Scope.accounts)
            Text("Posts").tag(Scope.posts)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, DreamMetric.screen)
        .onChange(of: scope) { _, _ in SoundManager.shared.play(.tap) }
    }

    // MARK: - Results

    private var results: some View {
        ScrollView {
            LazyVStack(spacing: DreamMetric.md) {
                if trimmedQuery.isEmpty {
                    promptState
                } else if isSearching && currentIsEmpty {
                    ProgressView()
                        .tint(Color.dreamPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, DreamMetric.xl)
                } else if currentIsEmpty {
                    emptyState
                } else {
                    switch scope {
                    case .accounts:
                        ForEach(accounts) { person in
                            FollowRow(
                                person: person,
                                isFollowing: followedHandles.contains(person.username.lowercased()),
                                isMe: !myHandle.isEmpty && person.username.lowercased() == myHandle,
                                onToggleFollow: { toggleFollow(person) }
                            )
                        }
                    case .posts:
                        ForEach(posts, id: \.id) { record in
                            PostResultRow(
                                record: record,
                                photo: postAvatars[record.authorUsername.lowercased()]
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, DreamMetric.screen)
            .padding(.top, DreamMetric.xs)
            .padding(.bottom, DreamMetric.xl)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var promptState: some View {
        emptyMessage(
            icon: "magnifyingglass",
            title: "Search the feed",
            subtitle: "Find dreamers by name or @handle, and dreams by what's in them."
        )
    }

    private var emptyState: some View {
        emptyMessage(
            icon: scope == .accounts ? "person.slash" : "moon.zzz",
            title: scope == .accounts ? "No dreamers found" : "No dreams found",
            subtitle: scope == .accounts
                ? "Try a different name or @handle."
                : "Try different words — search looks at a dream's title and text."
        )
    }

    private func emptyMessage(icon: String, title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
        VStack(spacing: DreamMetric.md) {
            Image(systemName: icon)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Color.dreamPrimary)
            Text(title)
                .font(.dreamSectionHeader)
            Text(subtitle)
                .font(.dreamBodyText)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, DreamMetric.xxl)
        .padding(.horizontal, DreamMetric.lg)
    }

    // MARK: - Actions

    private func toggleFollow(_ person: FollowProfile) {
        let willFollow = !followedHandles.contains(person.username.lowercased())
        store.setFollow(username: person.username, following: willFollow)
        SoundManager.shared.play(willFollow ? .shimmer : .tap)
    }

    /// Debounce keystrokes, then search both tabs so switching between them is
    /// instant. A blank field clears results without a round-trip.
    private func scheduleSearch(_ raw: String) {
        searchTask?.cancel()
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            accounts = []
            posts = []
            postAvatars = [:]
            searchedQuery = nil
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await runSearch(value)
        }
    }

    private func runSearch(_ value: String) async {
        async let accountsResult = auth.searchProfiles(value)
        async let postsResult = store.searchPosts(value)
        let (foundAccounts, foundPosts) = await (accountsResult, postsResult)
        // Ignore a result that arrives after the query has moved on.
        guard value == trimmedQuery else { return }
        accounts = foundAccounts
        posts = foundPosts
        searchedQuery = value
        isSearching = false
        await loadPostAvatars()
    }

    /// Fetch the post authors' avatars by @handle (posts don't carry a photo),
    /// merging so already-resolved photos stick.
    private func loadPostAvatars() async {
        let handles = Set(posts.map(\.authorUsername)).filter { !$0.isEmpty }
        let missing = handles.filter { postAvatars[$0.lowercased()] == nil }
        guard !missing.isEmpty else { return }
        let fetched = await auth.avatars(forUsernames: Array(missing))
        guard !fetched.isEmpty else { return }
        postAvatars.merge(fetched) { _, new in new }
    }
}

// MARK: - Post result row

/// A shared dream in the Posts search results: mood, title, a snippet, and the
/// author. Tapping opens a read-only detail.
private struct PostResultRow: View {
    let record: FeedPostRecord
    let photo: Data?

    private var mood: Dream.Mood { Dream.Mood(rawValue: record.mood ?? "") ?? .vivid }

    var body: some View {
        NavigationLink {
            SearchPostDetailView(record: record, authorPhoto: photo)
        } label: {
            HStack(spacing: DreamMetric.md) {
                MoodOrb(tint: mood.tint, diameter: 38, bloom: false)

                VStack(alignment: .leading, spacing: 3) {
                    Text(record.title)
                        .font(.dreamBody(15, .semibold))
                        .foregroundStyle(Color.dreamText)
                        .lineLimit(1)
                    if !record.dreamDescription.isEmpty {
                        Text(record.dreamDescription)
                            .font(.dreamCaption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    HStack(spacing: 5) {
                        FeedAvatar(photoData: photo, name: record.authorName, size: 18)
                        Text("@\(record.authorUsername)")
                            .font(.dreamCaption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.top, 1)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.dreamCaption)
                    .foregroundStyle(.secondary)
            }
            .padding(DreamMetric.lg)
            .dreamCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Read-only post detail

/// A read-only look at a shared dream found in search — it may belong to any
/// dreamer and isn't part of the local library, so (unlike `DreamDetailView`)
/// there's nothing to edit here. The author header opens their public profile.
struct SearchPostDetailView: View {
    let record: FeedPostRecord
    let authorPhoto: Data?

    private var mood: Dream.Mood { Dream.Mood(rawValue: record.mood ?? "") ?? .vivid }

    private var author: FeedAuthor {
        FeedAuthor(username: record.authorUsername, name: record.authorName, photo: authorPhoto)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                authorHeader
                titleHeader

                if !record.dreamDescription.isEmpty {
                    Text(record.dreamDescription)
                        .font(.dreamBody(16))
                        .lineSpacing(5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let tags = record.tags, !tags.isEmpty {
                    tagsSection(tags)
                }

                aiSection
            }
            .padding(20)
        }
        .tabBarClearance()
        .background { DreamBackground() }
        .navigationTitle(record.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var authorHeader: some View {
        NavigationLink {
            PublicProfileView(author: author)
        } label: {
            HStack(spacing: DreamMetric.md) {
                FeedAvatar(photoData: authorPhoto, name: record.authorName, size: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(record.authorName)
                        .font(.dreamBody(15, .semibold))
                        .foregroundStyle(Color.dreamText)
                    HStack(spacing: 4) {
                        Text("@\(record.authorUsername)")
                            .foregroundStyle(Color.dreamPrimary)
                        Text("·")
                            .foregroundStyle(.secondary)
                        Text(record.createdAt, format: .relative(presentation: .named))
                            .foregroundStyle(.secondary)
                    }
                    .font(.dreamCaption)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.dreamCaption)
                    .foregroundStyle(.secondary)
            }
            .padding(DreamMetric.md)
            .dreamCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var titleHeader: some View {
        HStack(spacing: DreamMetric.md) {
            MoodOrb(tint: mood.tint, diameter: 44, bloom: false)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.title)
                    .font(.dreamDisplay(24))
                    .fixedSize(horizontal: false, vertical: true)
                Text(localized(mood.rawValue))
                    .font(.dreamCaption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private func tagsSection(_ tags: [String]) -> some View {
        VStack(alignment: .leading, spacing: DreamMetric.sm) {
            Text("Tags")
                .font(.dreamSectionHeader)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tags, id: \.self) { tag in
                        Text(tag)
                            .font(.dreamBody(12, .semibold))
                            .padding(.horizontal, DreamMetric.md)
                            .padding(.vertical, DreamMetric.xs + 2)
                            .background(mood.tint.opacity(0.18), in: .capsule)
                            .foregroundStyle(mood.tint)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var aiSection: some View {
        if let category = record.aiCategory, let meaning = record.aiMeaning {
            VStack(alignment: .leading, spacing: DreamMetric.md) {
                HStack(spacing: DreamMetric.sm) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Color.dreamPrimary)
                    Text("AI Insight")
                        .font(.dreamCardTitle)
                }

                Text(category)
                    .font(.dreamCaption)
                    .padding(.horizontal, DreamMetric.md)
                    .padding(.vertical, DreamMetric.xs + 2)
                    .background(Color.dreamPrimary.opacity(0.18), in: .capsule)
                    .foregroundStyle(Color.dreamPrimary)

                Text(meaning)
                    .font(.dreamBodyText)
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)

                if let themes = record.aiThemes, !themes.isEmpty {
                    VStack(alignment: .leading, spacing: DreamMetric.sm) {
                        Text("Themes")
                            .font(.dreamBody(13, .semibold))
                            .foregroundStyle(.secondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(themes, id: \.self) { theme in
                                    Text(theme.capitalized)
                                        .font(.dreamBody(12, .semibold))
                                        .padding(.horizontal, DreamMetric.md)
                                        .padding(.vertical, DreamMetric.xs + 2)
                                        .background(Color.dreamPrimary.opacity(0.18), in: .capsule)
                                        .foregroundStyle(Color.dreamPrimary)
                                }
                            }
                        }
                    }
                    .padding(.top, DreamMetric.xs)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DreamMetric.xl)
            .dreamCard()
        }
    }
}
