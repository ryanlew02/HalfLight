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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DreamMetric.xl) {
                header
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
        if let existing = follows.first {
            modelContext.delete(existing)
            SoundManager.shared.play(.tap)
        } else {
            modelContext.insert(Follow(username: author.username))
            SoundManager.shared.play(.shimmer)
        }
        try? modelContext.save()
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
