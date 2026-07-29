//
//  BlockedAccountsView.swift
//  HalfLight
//
//  Settings › Account › Blocked Accounts — the way back out of a block. Blocking
//  happens from a dream, a comment or a profile (see `BlockUser.swift`); this is
//  the only place it can be undone, so the list is deliberately plain and the
//  Unblock button is never more than one tap away.
//

import SwiftUI

struct BlockedAccountsView: View {
    @Environment(AuthService.self) private var auth
    @Environment(DreamStore.self) private var store

    @State private var blocked: [FollowProfile] = []
    @State private var isLoading = true
    /// The @handle being unblocked, so its row shows a spinner instead of the button.
    @State private var unblocking: String?

    var body: some View {
        List {
            if isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView().tint(Color.dreamPrimary)
                        Spacer()
                    }
                }
                .listRowBackground(Color.dreamSurface)
            } else if blocked.isEmpty {
                Section {
                    emptyState
                }
                .listRowBackground(Color.dreamSurface)
            } else {
                Section {
                    ForEach(blocked) { person in
                        row(person)
                    }
                } footer: {
                    Text("Blocked dreamers can't see your dreams or comments, and you can't see theirs. They aren't told that you blocked them.")
                        .font(.dreamCaption)
                }
                .listRowBackground(Color.dreamSurface)
            }
        }
        .scrollContentBackground(.hidden)
        .background { DreamBackground() }
        .navigationTitle("Blocked Accounts")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await load() }
    }

    private func row(_ person: FollowProfile) -> some View {
        HStack(spacing: DreamMetric.md) {
            FeedAvatar(photoData: person.photo, name: person.name, size: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(person.name.isEmpty ? "@\(person.username)" : person.name)
                    .font(.dreamBody(15, .semibold))
                    .foregroundStyle(Color.dreamText)
                    .lineLimit(1)
                Text("@\(person.username)")
                    .font(.dreamCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if unblocking == person.username {
                ProgressView().tint(Color.dreamPrimary)
            } else {
                Button("Unblock") {
                    SoundManager.shared.play(.tap)
                    Task { await unblock(person) }
                }
                .font(.dreamBody(14, .semibold))
                .foregroundStyle(Color.dreamPrimary)
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }

    private var emptyState: some View {
        VStack(spacing: DreamMetric.sm) {
            Image(systemName: "hand.raised.slash")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Color.dreamPrimary)
            Text("No blocked accounts")
                .font(.dreamBody(15, .semibold))
            Text("You can block someone from their profile, or by pressing and holding one of their dreams or comments.")
                .font(.dreamCaption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DreamMetric.lg)
    }

    private func load() async {
        blocked = await auth.blockedAccounts()
        isLoading = false
    }

    /// Lift the block, then pull the feed again so their dreams can come back.
    private func unblock(_ person: FollowProfile) async {
        unblocking = person.username
        defer { unblocking = nil }
        guard await auth.unblockUser(username: person.username) else { return }
        blocked.removeAll { $0.username == person.username }
        store.reconcileFeed()
    }
}
