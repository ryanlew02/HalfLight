//
//  FeedView.swift
//  HalfLight
//
//  The social feed of dreams: browse shared dreams, like them, and (soon) leave
//  comments. Posts are created by sharing a dream from its detail screen.
//

import SwiftUI
import SwiftData

struct FeedView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(DreamStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(AuthService.self) private var auth
    /// Presents the sign-up / log-in sheet when a signed-out dreamer taps the gate.
    @State private var showAuth = false
    // The full set of posts; `FeedRanker` decides the order (see `rankedPosts`).
    // Newest-first here only gives a stable input and a sensible cold-start order.
    @Query(sort: \FeedPost.createdAt, order: .reverse) private var posts: [FeedPost]
    /// Who the dreamer follows, a ranking signal.
    @Query private var follows: [Follow]
    // Mirror the profile so the feed re-snapshots author info the moment any of
    // these change (and each time the feed is shown), without a polling timer.
    @AppStorage("profilePhoto") private var profilePhoto: Data?
    @AppStorage("userName") private var userName = "Dreamer"
    @AppStorage("userUsername") private var userUsername = ""
    /// The local dreams behind the posts, so a card can show the live AI analysis /
    /// tags and tapping it can open the full dream. (The feed only holds the
    /// dreamer's own shared dreams for now, so the source dream is always local.)
    @Query private var dreams: [Dream]
    /// The dream (plus its author) a tapped card is navigating to.
    @State private var selectedRoute: FeedDreamRoute?
    /// The author whose profile a tapped header is navigating to.
    @State private var selectedProfile: FeedAuthor?
    /// The post whose comments are open in a sheet.
    @State private var commentsPost: FeedPost?
    /// The ranked order, captured as ids so the feed doesn't reshuffle mid-scroll
    /// when a like or impression lands; recomputed when the post set changes or the
    /// feed reappears. The view always renders live posts in this order.
    @State private var orderedIDs: [UUID] = []
    /// Posts whose impression has already been counted this session.
    @State private var impressed: Set<UUID> = []
    /// Authors' profile photos fetched by @handle, keyed by lowercased username, so
    /// other dreamers show real avatars instead of initials. Own posts already carry
    /// a fresh snapshot; this fills in everyone else.
    @State private var remoteAvatars: [String: Data] = [:]

    private var dreamsByID: [UUID: Dream] {
        Dictionary(dreams.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var followedUsernames: Set<String> {
        Set(follows.map { $0.username.lowercased() })
    }

    /// Live posts in the last-computed ranked order; new/removed posts are handled
    /// on the next `refreshRanking()`.
    private var rankedPosts: [FeedPost] {
        let byID = Dictionary(posts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ordered = orderedIDs.compactMap { byID[$0] }
        // Fall back to the raw query before the first ranking pass runs.
        return ordered.isEmpty ? posts : ordered
    }

    private func refreshRanking() {
        orderedIDs = FeedRanker.rank(
            posts: posts,
            dreamsByID: dreamsByID,
            followedUsernames: followedUsernames
        ).map(\.id)
    }

    /// Count one impression per post per session — the denominator of the
    /// like-per-view conversion rate the ranker reads as virality. Goes through the
    /// store so it's mirrored to Supabase.
    private func recordImpression(_ post: FeedPost) {
        guard impressed.insert(post.id).inserted else { return }
        store.recordView(post)
    }

    /// The photo to render for a post's author: the snapshot on the post (fresh for
    /// your own posts) and, for everyone else, the avatar fetched by @handle.
    private func photo(for post: FeedPost) -> Data? {
        post.authorPhoto ?? remoteAvatars[post.authorUsername.lowercased()]
    }

    /// Fetch the avatars of authors we don't already have, keyed by @handle. Merges
    /// so resolved photos persist as `reconcileFeed` streams more posts in.
    private func loadFeedAvatars() async {
        let usernames = Set(posts.map(\.authorUsername)).filter { !$0.isEmpty }
        let missing = usernames.filter { remoteAvatars[$0.lowercased()] == nil }
        guard !missing.isEmpty else { return }
        let fetched = await auth.avatars(forUsernames: Array(missing))
        guard !fetched.isEmpty else { return }
        remoteAvatars.merge(fetched) { _, new in new }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Matches the Journal / Lucid Path heading style (a left-aligned
                // `.dreamTitle` instead of the system inline nav title).
                Text("Feed")
                    .font(.dreamTitle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 12)

                Group {
                    if !auth.isSignedIn {
                        // The feed is a shared, multi-user space — gate it behind an
                        // account so likes/comments are attributable.
                        signInGate
                    } else if posts.isEmpty {
                        emptyState
                    } else {
                        // Build the dream lookup once per render and thread it down,
                        // rather than rebuilding the whole dictionary for every card.
                        feedPager(dreamsByID: dreamsByID)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background { DreamBackground() }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $selectedRoute) { route in
                DreamDetailView(dream: route.dream, feedAuthor: route.author, postedAt: route.postedAt)
            }
            .navigationDestination(item: $selectedProfile) { author in
                PublicProfileView(author: author)
            }
            .sheet(item: $commentsPost) { post in
                CommentsView(post: post)
            }
            .sheet(isPresented: $showAuth) {
                AuthView()
            }
            // The feed stays alive across tab switches (it isn't rebuilt), so refresh
            // whenever the Feed tab becomes active — `initial: true` covers the first
            // time it's opened.
            .onChange(of: router.tab, initial: true) { _, tab in
                guard tab == .feed, auth.isSignedIn else { return }
                store.reconcileFeed()
                store.refreshFeedAuthors()
                refreshRanking()
            }
            // Re-rank when posts are added/removed or the follow set changes, but
            // not on every like/impression — that would reshuffle under the user.
            .onChange(of: posts.count) { _, _ in refreshRanking() }
            .onChange(of: follows.count) { _, _ in refreshRanking() }
            // Fetch authors' avatars on first appearance and whenever the post set
            // grows (e.g. `reconcileFeed` syncing more dreamers' posts in).
            .task(id: posts.count) { await loadFeedAvatars() }
            .onChange(of: profilePhoto) { _, _ in store.refreshFeedAuthors() }
            .onChange(of: userName) { _, _ in store.refreshFeedAuthors() }
            .onChange(of: userUsername) { _, _ in store.refreshFeedAuthors() }
        }
    }

    /// One dream per screen; swipe vertically to snap to the next.
    /// `containerRelativeFrame(.vertical)` sizes each page to exactly one screen so
    /// `.paging` advances by a single dream, while the card keeps an inset margin
    /// (it doesn't run to the screen edges).
    private func feedPager(dreamsByID: [UUID: Dream]) -> some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(rankedPosts) { post in
                    FeedPostCard(
                        post: post,
                        dream: dreamsByID[post.dreamID],
                        resolvedPhoto: photo(for: post),
                        onOpen: {
                            if let dream = dreamsByID[post.dreamID] {
                                selectedRoute = FeedDreamRoute(
                                    dream: dream,
                                    author: FeedAuthor(
                                        username: post.authorUsername,
                                        name: post.authorName,
                                        photo: photo(for: post)
                                    ),
                                    postedAt: post.createdAt
                                )
                            }
                        },
                        onOpenProfile: {
                            selectedProfile = FeedAuthor(
                                username: post.authorUsername,
                                name: post.authorName,
                                photo: photo(for: post)
                            )
                        },
                        onToggleLike: { toggleLike(post) },
                        onComment: { commentsPost = post },
                        onImpression: { recordImpression(post) }
                    )
                    .padding(.horizontal, DreamMetric.screen)
                    .padding(.bottom, DreamMetric.md)
                    .containerRelativeFrame(.vertical)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .tabBarClearance()
    }

    /// Shown to signed-out dreamers: the feed needs an account so engagement is
    /// attributable. Tapping the button opens the sign-up / log-in sheet.
    private var signInGate: some View {
        VStack(spacing: DreamMetric.md) {
            Image(systemName: "person.2")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Color.dreamPrimary)
            Text("Join the dream feed")
                .font(.dreamSectionHeader)
            Text("Sign up or log in to see dreams from other dreamers, and to like and comment on them.")
                .font(.dreamBodyText)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Sign Up or Log In") {
                SoundManager.shared.play(.tap)
                showAuth = true
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.top, DreamMetric.sm)
        }
        .padding(DreamMetric.xl)
    }

    private var emptyState: some View {
        VStack(spacing: DreamMetric.md) {
            Image(systemName: "moon.stars")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Color.dreamPrimary)
            Text("No dreams shared yet")
                .font(.dreamSectionHeader)
            Text("Set a dream's visibility to Public to share it to the feed.")
                .font(.dreamBodyText)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(DreamMetric.xl)
    }

    /// Flip the like state (local + Supabase) via the store.
    private func toggleLike(_ post: FeedPost) {
        store.toggleLike(post)
    }
}

/// A feed tap target: the dream to open plus the author snapshot and post date to
/// show in its detail header. Identified by the dream so the push is stable.
struct FeedDreamRoute: Identifiable, Hashable {
    let dream: Dream
    let author: FeedAuthor
    let postedAt: Date

    var id: UUID { dream.id }
}

#Preview("Light") {
    FeedView()
        .modelContainer(PreviewData.container)
        .environment(PreviewData.store)
        .environment(AuthService())
}

#Preview("Dark") {
    FeedView()
        .modelContainer(PreviewData.container)
        .environment(PreviewData.store)
        .environment(AuthService())
        .preferredColorScheme(.dark)
}
