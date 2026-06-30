//
//  FollowListView.swift
//  HalfLight
//
//  The followers / following lists behind the counts on a profile. Both the
//  Profile tab (your own graph) and a tapped feed profile (someone else's) open
//  this, switching between the two lists with a segmented control. Each row opens
//  that dreamer's public profile.
//
//  The lists come from the `followers_of` / `following_of` Supabase RPCs (see
//  FollowGraph migration) since the `follows` table's RLS hides other users' rows
//  from a plain query.
//

import SwiftUI

/// Which list a follow screen opens on (and which the segmented control shows).
enum FollowTab: Hashable {
    case followers, following
}

struct FollowListView: View {
    /// The dreamer whose graph this shows (without the leading "@").
    let username: String
    /// Their display name, for the navigation title.
    let displayName: String

    @Environment(AuthService.self) private var auth
    @State private var tab: FollowTab
    @State private var followers: [FollowProfile] = []
    @State private var following: [FollowProfile] = []
    @State private var isLoading = true

    init(username: String, displayName: String, initialTab: FollowTab) {
        self.username = username
        self.displayName = displayName
        _tab = State(initialValue: initialTab)
    }

    private var rows: [FollowProfile] {
        tab == .followers ? followers : following
    }

    var body: some View {
        ScrollView {
            VStack(spacing: DreamMetric.lg) {
                picker
                content
            }
            .padding(DreamMetric.screen)
        }
        .tabBarClearance()
        .background { DreamBackground() }
        .navigationTitle(displayName.isEmpty ? "@\(username)" : displayName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await load() }
    }

    private var picker: some View {
        Picker("List", selection: $tab) {
            Text("\(followers.count) Followers").tag(FollowTab.followers)
            Text("\(following.count) Following").tag(FollowTab.following)
        }
        .pickerStyle(.segmented)
        .onChange(of: tab) { _, _ in SoundManager.shared.play(.tap) }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView()
                .tint(Color.dreamPrimary)
                .frame(maxWidth: .infinity)
                .padding(.top, DreamMetric.xl)
        } else if rows.isEmpty {
            Text(tab == .followers ? "No followers yet." : "Not following anyone yet.")
                .font(.dreamBodyText)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, DreamMetric.xl)
        } else {
            VStack(spacing: DreamMetric.md) {
                ForEach(rows) { person in
                    NavigationLink {
                        PublicProfileView(author: FeedAuthor(
                            username: person.username,
                            name: person.name,
                            photo: person.photo
                        ))
                    } label: {
                        FollowRow(person: person)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func load() async {
        let followers = await auth.followers(of: username)
        let following = await auth.following(of: username)
        self.followers = followers
        self.following = following
        isLoading = false
    }
}

/// One dreamer in a follow list: avatar, name, and @handle.
private struct FollowRow: View {
    let person: FollowProfile

    var body: some View {
        HStack(spacing: DreamMetric.md) {
            FeedAvatar(photoData: person.photo, name: person.name, size: 44)

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

            Image(systemName: "chevron.right")
                .font(.dreamCaption)
                .foregroundStyle(.secondary)
        }
        .padding(DreamMetric.lg)
        .dreamCard()
    }
}

/// The tappable "N Followers · N Following" strip shown on a profile header. Each
/// count pushes the matching list. Lives in its own view so the Profile tab and a
/// public profile render an identical control.
struct FollowStatsBar: View {
    let username: String
    let displayName: String
    let counts: FollowCounts

    var body: some View {
        HStack(spacing: 0) {
            stat(count: counts.followers, label: "Followers", tab: .followers)
            Divider()
                .frame(height: 30)
                .overlay(Color.dreamText.opacity(0.12))
            stat(count: counts.following, label: "Following", tab: .following)
        }
        .frame(maxWidth: 320)
    }

    private func stat(count: Int, label: LocalizedStringKey, tab: FollowTab) -> some View {
        NavigationLink {
            FollowListView(username: username, displayName: displayName, initialTab: tab)
        } label: {
            VStack(spacing: 2) {
                Text("\(count)")
                    .font(.dreamBody(18, .bold))
                    .foregroundStyle(Color.dreamText)
                Text(label)
                    .font(.dreamBody(12, .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
