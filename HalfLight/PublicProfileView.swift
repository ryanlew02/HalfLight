//
//  PublicProfileView.swift
//  HalfLight
//
//  A read-only look at another dreamer's profile, reached by tapping their photo,
//  name, or @handle on a feed card. For now it shows the author snapshot captured
//  on their posts plus the dreams they've shared to the feed; once a multi-user
//  backend exists this is where their fetched profile (bio, stats) will render.
//

import SwiftUI
import SwiftData

/// The identity needed to open a profile from the feed — a value type so it can
/// drive `navigationDestination(item:)`. Keyed by the (unique) handle.
struct FeedAuthor: Identifiable, Hashable {
    var username: String
    var name: String
    var photo: Data?

    var id: String { username }
}

struct PublicProfileView: View {
    let author: FeedAuthor

    @Environment(\.modelContext) private var modelContext
    @Environment(AuthService.self) private var auth
    @Environment(DreamStore.self) private var store
    @AppStorage("lucidSectionsCompleted") private var lucidSectionsCompleted = 0
    @AppStorage("questBankedXP") private var questBankedXP = 0
    /// This author's shared dreams, newest first.
    @Query private var posts: [FeedPost]
    /// Local dreams, so a shared dream can be opened in full.
    @Query private var dreams: [Dream]
    /// The follow row for this author, if one exists (empty ⇒ not following).
    @Query private var follows: [Follow]
    @State private var selectedDream: Dream?

    init(author: FeedAuthor) {
        self.author = author
        let username = author.username
        _posts = Query(
            filter: #Predicate<FeedPost> { $0.authorUsername == username },
            sort: \.createdAt,
            order: .reverse
        )
        _follows = Query(filter: #Predicate<Follow> { $0.username == username })
    }

    /// Whether this profile belongs to the signed-in dreamer (no Follow button).
    private var isOwnProfile: Bool {
        let me = (auth.username ?? UserDefaults.standard.string(forKey: "userUsername") ?? "")
            .lowercased()
        return !me.isEmpty && me == author.username.lowercased()
    }

    private var isFollowing: Bool { !follows.isEmpty }

    private var dreamsByID: [UUID: Dream] {
        Dictionary(dreams.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: - Progression / achievements
    //
    // For your own profile we measure your whole dream library (matching the
    // Profile tab). For someone else we can only see the dreams they've shared, so
    // their rank and badges are derived from those until a backend serves real
    // per-user stats.

    /// The dreams the rank and achievements are measured against.
    private var statDreams: [Dream] {
        if isOwnProfile { return dreams }
        let sharedIDs = Set(posts.map(\.dreamID))
        return dreams.filter { sharedIDs.contains($0.id) }
    }

    private var lucidSections: Int { isOwnProfile ? lucidSectionsCompleted : 0 }

    private var stats: AchievementStats {
        let journaled = Set(statDreams.map { Calendar.current.startOfDay(for: $0.date) })
        return AchievementStats(dreams: statDreams, journaledDays: journaled, lucidSections: lucidSections)
    }

    private var totalXP: Int {
        if isOwnProfile {
            return store.totalXP(dreams: dreams, lucidSections: lucidSectionsCompleted, questBankedXP: questBankedXP)
        }
        let journaledDays = Set(statDreams.map { Calendar.current.startOfDay(for: $0.date) }).count
        return DreamProgression.totalXP(
            journaledDays: journaledDays,
            lucidSections: 0,
            achievementXP: Achievement.unlockedXP(for: stats)
        )
    }

    private var level: Int { DreamProgression.level(forXP: totalXP) }
    private var rank: DreamProgression.Rank { DreamProgression.rank(forLevel: level) }

    private var unlockedAchievements: [Achievement] {
        Achievement.all.filter { $0.isUnlocked(for: stats) }
    }

    /// The bio, available only for your own profile until a backend serves others'.
    private var bio: String? { isOwnProfile ? auth.bio : nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DreamMetric.xl) {
                header
                bioCard
                achievementsCard
                sharedDreamsSection
            }
            .padding(DreamMetric.screen)
        }
        .tabBarClearance()
        .background { DreamBackground() }
        .navigationTitle("@\(author.username)")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .navigationDestination(item: $selectedDream) { dream in
            DreamDetailView(dream: dream)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .center, spacing: DreamMetric.md) {
            FeedAvatar(photoData: author.photo, name: author.name, size: 96)

            VStack(spacing: 2) {
                Text(author.name)
                    .font(.dreamDisplay(28))
                Text("@\(author.username)")
                    .font(.dreamBody(14, .semibold))
                    .foregroundStyle(Color.dreamPrimary)
            }

            rankBadge

            Text(sharedCountLabel)
                .font(.dreamBody(13, .medium))
                .foregroundStyle(.secondary)

            if !isOwnProfile {
                followButton
                    .frame(maxWidth: 240)
                    .padding(.top, DreamMetric.xs)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Level + rank, in the same capsule treatment as the Profile tab.
    private var rankBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 10, weight: .bold))
            Text("Level \(level) · \(rank.name)")
                .font(.dreamBody(12, .bold))
        }
        .foregroundStyle(Color.dreamPrimary)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color.dreamPrimary.opacity(0.14), in: .capsule)
    }

    // MARK: - Bio

    @ViewBuilder
    private var bioCard: some View {
        if let bio, !bio.isEmpty {
            Text(bio)
                .font(.dreamBody(15))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DreamMetric.lg)
                .dreamCard()
        }
    }

    // MARK: - Achievements

    private var achievementsCard: some View {
        VStack(alignment: .leading, spacing: DreamMetric.md) {
            HStack(spacing: DreamMetric.sm) {
                Image(systemName: "rosette")
                    .foregroundStyle(Color.dreamPrimary)
                Text("Achievements")
                    .font(.dreamSectionHeader)
                Spacer(minLength: 0)
                Text("\(unlockedAchievements.count) of \(Achievement.all.count)")
                    .font(.dreamCaption)
                    .foregroundStyle(.secondary)
            }

            if unlockedAchievements.isEmpty {
                Text("No achievements yet.")
                    .font(.dreamBodyText)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: DreamMetric.lg) {
                        ForEach(unlockedAchievements.prefix(10)) { achievement in
                            VStack(spacing: 6) {
                                AchievementMedallion(
                                    symbol: achievement.symbol,
                                    tint: achievement.tint,
                                    unlocked: true,
                                    size: 56,
                                    bloom: false
                                )
                                Text(achievement.title)
                                    .font(.dreamBody(11, .semibold))
                                    .multilineTextAlignment(.center)
                                    .frame(width: 72)
                            }
                        }
                    }
                    .padding(.vertical, DreamMetric.xs)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DreamMetric.lg)
        .dreamCard()
    }

    @ViewBuilder
    private var followButton: some View {
        if isFollowing {
            Button(action: toggleFollow) {
                Label("Following", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(GhostButtonStyle())
        } else {
            Button(action: toggleFollow) {
                Text("Follow")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    private func toggleFollow() {
        let willFollow = !isFollowing
        store.setFollow(username: author.username, following: willFollow)
        SoundManager.shared.play(willFollow ? .shimmer : .tap)
    }

    private var sharedCountLabel: String {
        posts.count == 1 ? "1 dream shared" : "\(posts.count) dreams shared"
    }

    // MARK: - Shared dreams

    @ViewBuilder
    private var sharedDreamsSection: some View {
        if posts.isEmpty {
            Text("No shared dreams yet.")
                .font(.dreamBodyText)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, DreamMetric.xl)
        } else {
            VStack(alignment: .leading, spacing: DreamMetric.md) {
                Text("Shared dreams")
                    .font(.dreamSectionHeader)

                ForEach(posts) { post in
                    sharedDreamRow(post)
                }
            }
        }
    }

    private func sharedDreamRow(_ post: FeedPost) -> some View {
        let dream = dreamsByID[post.dreamID]
        return Button {
            if let dream {
                SoundManager.shared.play(.tap)
                selectedDream = dream
            }
        } label: {
            HStack(spacing: DreamMetric.md) {
                if let mood = dream?.mood {
                    MoodOrb(tint: mood.tint, diameter: 34, bloom: false)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(post.title)
                        .font(.dreamBody(15, .semibold))
                        .foregroundStyle(Color.dreamText)
                        .lineLimit(1)
                    Text(post.createdAt, format: .relative(presentation: .named))
                        .font(.dreamCaption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if dream != nil {
                    Image(systemName: "chevron.right")
                        .font(.dreamCaption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(DreamMetric.lg)
            .dreamCard()
        }
        .buttonStyle(.plain)
        .disabled(dream == nil)
    }
}
