//
//  NotificationsView.swift
//  HalfLight
//
//  The dreamer's activity inbox, reached from the bell in the Profile header.
//  Lists likes and comments others left on the dreamer's shared dreams, served
//  from the `notifications` table (written by DB triggers) and cached locally as
//  `AppNotification` via `DreamStore.reconcileNotifications()`.
//
//  Opening the inbox marks everything read (locally and on the server), which
//  clears the bell badge; rows unread on entry stay highlighted while reading.
//

import SwiftUI
import SwiftData

struct NotificationsView: View {
    @Environment(AuthService.self) private var auth
    @Environment(DreamStore.self) private var store

    @Query(sort: \AppNotification.createdAt, order: .reverse)
    private var notifications: [AppNotification]
    @Query private var posts: [FeedPost]

    /// IDs that were unread when the screen opened, so their dot persists while
    /// we're reading even after `markNotificationsRead()` flips them.
    @State private var unreadOnOpen: Set<UUID> = []
    /// Actor avatars fetched by @handle, keyed by lowercased username.
    @State private var avatars: [String: Data] = [:]
    /// The post whose comment thread is presented when a row is tapped.
    @State private var selectedPost: FeedPost?

    var body: some View {
        ZStack {
            DreamBackground()

            if notifications.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .navigationTitle("Activity")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(item: $selectedPost) { post in
            CommentsView(post: post)
        }
        .task {
            store.reconcileNotifications()
            unreadOnOpen = Set(notifications.filter { !$0.isRead }.map(\.id))
            store.markNotificationsRead()
        }
        .task(id: notifications.count) { await loadAvatars() }
    }

    // MARK: - List

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: DreamMetric.md) {
                ForEach(notifications) { note in
                    Button { open(note) } label: { row(note) }
                        .buttonStyle(.plain)
                }
            }
            .padding(DreamMetric.screen)
        }
    }

    private func row(_ note: AppNotification) -> some View {
        HStack(alignment: .top, spacing: DreamMetric.md) {
            icon(for: note)

            VStack(alignment: .leading, spacing: 3) {
                title(for: note)

                if note.kind == .comment, let text = note.commentText {
                    Text(text)
                        .font(.dreamBodyText)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(note.createdAt, format: .relative(presentation: .named))
                    .font(.dreamCaption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if unreadOnOpen.contains(note.id) {
                Circle()
                    .fill(Color.dreamPrimary)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DreamMetric.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dreamCard()
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func icon(for note: AppNotification) -> some View {
        switch note.kind {
        case .comment:
            FeedAvatar(photoData: photo(for: note), name: note.actorName, size: 40)
        case .like:
            ZStack {
                FeedAvatar(photoData: photo(for: note), name: note.actorName, size: 40)
                // A small heart marker so a like reads as a like at a glance.
                Image(systemName: "heart.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(3)
                    .background(Color.dreamAccent, in: .circle)
                    .offset(x: 14, y: 14)
            }
            .frame(width: 40, height: 40)
        }
    }

    private func title(for note: AppNotification) -> some View {
        let verb = note.kind == .like ? " liked " : " commented on "
        return (
            Text(note.actorName.isEmpty ? "Someone" : note.actorName)
                .font(.dreamBody(14, .semibold)).foregroundStyle(Color.dreamText)
            + Text(verb)
                .font(.dreamBody(14)).foregroundStyle(.secondary)
            + Text("“\(note.postTitle)”")
                .font(.dreamBody(14, .semibold)).foregroundStyle(Color.dreamText)
        )
        .fixedSize(horizontal: false, vertical: true)
    }

    private var emptyState: some View {
        VStack(spacing: DreamMetric.sm) {
            Image(systemName: "bell.slash")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.dreamPrimary)
            Text("No activity yet")
                .font(.dreamSectionHeader)
            Text("Likes and comments on your shared dreams will show up here.")
                .font(.dreamBodyText)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(DreamMetric.xl)
    }

    // MARK: - Avatars / actions

    private func photo(for note: AppNotification) -> Data? {
        avatars[note.actorUsername.lowercased()]
    }

    /// Fetch any actor avatars we don't already have, keyed by @handle.
    private func loadAvatars() async {
        let handles = Set(notifications.map(\.actorUsername)).filter { !$0.isEmpty }
        let missing = handles.filter { avatars[$0.lowercased()] == nil }
        guard !missing.isEmpty else { return }
        let fetched = await auth.avatars(forUsernames: Array(missing))
        guard !fetched.isEmpty else { return }
        avatars.merge(fetched) { _, new in new }
    }

    private func open(_ note: AppNotification) {
        SoundManager.shared.play(.tap)
        guard let id = note.postID else { return }
        selectedPost = posts.first { $0.id == id }
    }
}
