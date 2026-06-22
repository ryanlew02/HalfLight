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

    var body: some View {
        NavigationStack {
            Group {
                if posts.isEmpty {
                    emptyState
                } else {
                    feedPager
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { DreamBackground() }
            .navigationTitle("Feed")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationDestination(item: $selectedRoute) { route in
                DreamDetailView(dream: route.dream, feedAuthor: route.author, postedAt: route.postedAt)
            }
            .navigationDestination(item: $selectedProfile) { author in
                PublicProfileView(author: author)
            }
            .sheet(item: $commentsPost) { post in
                CommentsView(post: post)
            }
            .task {
                store.reconcileFeed()
                store.refreshFeedAuthors()
                refreshRanking()
            }
            // Re-rank when posts are added/removed or the follow set changes, but
            // not on every like/impression — that would reshuffle under the user.
            .onChange(of: posts.count) { _, _ in refreshRanking() }
            .onChange(of: follows.count) { _, _ in refreshRanking() }
            .onChange(of: profilePhoto) { _, _ in store.refreshFeedAuthors() }
            .onChange(of: userName) { _, _ in store.refreshFeedAuthors() }
            .onChange(of: userUsername) { _, _ in store.refreshFeedAuthors() }
        }
    }

    /// One dream per screen; swipe vertically to snap to the next.
    /// `containerRelativeFrame(.vertical)` sizes each page to exactly one screen so
    /// `.paging` advances by a single dream, while the card keeps an inset margin
    /// (it doesn't run to the screen edges).
    private var feedPager: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(rankedPosts) { post in
                    FeedPostCard(
                        post: post,
                        dream: dreamsByID[post.dreamID],
                        onOpen: {
                            if let dream = dreamsByID[post.dreamID] {
                                selectedRoute = FeedDreamRoute(
                                    dream: dream,
                                    author: FeedAuthor(
                                        username: post.authorUsername,
                                        name: post.authorName,
                                        photo: post.authorPhoto
                                    ),
                                    postedAt: post.createdAt
                                )
                            }
                        },
                        onOpenProfile: {
                            selectedProfile = FeedAuthor(
                                username: post.authorUsername,
                                name: post.authorName,
                                photo: post.authorPhoto
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
}

#Preview("Dark") {
    FeedView()
        .modelContainer(PreviewData.container)
        .environment(PreviewData.store)
        .preferredColorScheme(.dark)
}
