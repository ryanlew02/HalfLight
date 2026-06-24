//
//  ProfileView.swift
//  HalfLight
//
//  The Profile tab: the dreamer's name, account status, and a way into
//  Settings. (Leaderboard / friends will live here later.)
//

import SwiftUI
import SwiftData
import PhotosUI
#if canImport(UIKit)
import UIKit
#endif

struct ProfileView: View {
    @Environment(AuthService.self) private var auth
    @Environment(AppRouter.self) private var router
    @Environment(DreamStore.self) private var store
    @Query private var dreams: [Dream]
    @AppStorage("userName") private var userName = "Dreamer"
    @AppStorage("lucidSectionsCompleted") private var lucidSectionsCompleted = 0
    @AppStorage("questBankedXP") private var questBankedXP = 0
    /// The dreamer's profile photo, stored as a cropped JPEG.
    @AppStorage("profilePhoto") private var profilePhotoData: Data?
    @State private var photoItem: PhotosPickerItem?
    /// The just-picked photo awaiting crop, presented in `PhotoCropView`.
    @State private var cropItem: CropItem?
    @State private var showAuth = false
    /// Drives the push into the Progress screen (from the card or the Home shortcut).
    @State private var showingProgress = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    bioCard
                    progressCard
                    accountCard
                    themesCard
                }
                .padding(20)
            }
            .tabBarClearance()
            .background { DreamBackground() }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showingProgress) {
                StatsView()
            }
            .onAppear { consumeProgressIntent() }
            .onChange(of: router.openProgress) { _, _ in consumeProgressIntent() }
            .sheet(isPresented: $showAuth) {
                AuthView()
            }
            #if canImport(UIKit)
            .fullScreenCover(item: $cropItem) { item in
                PhotoCropView(imageData: item.data) { cropped in
                    profilePhotoData = cropped
                    SoundManager.shared.play(.shimmer)
                }
            }
            #endif
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: DreamMetric.lg) {
            avatar

            VStack(alignment: .leading, spacing: 2) {
                Text(userName)
                    .font(.dreamDisplay(28))
                if let username = auth.username, !username.isEmpty {
                    Text("@\(username)")
                        .font(.dreamBody(14, .semibold))
                        .foregroundStyle(Color.dreamPrimary)
                }
                Text(auth.isSignedIn ? (auth.email ?? "Signed in") : "Not signed in")
                    .font(.dreamBody(13, .medium))
                    .foregroundStyle(.secondary)

                rankBadge
                    .padding(.top, 6)
            }

            Spacer()

            HStack(spacing: DreamMetric.lg) {
                if auth.isSignedIn {
                    NavigationLink {
                        EditProfileView()
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.title2)
                            .foregroundStyle(Color.dreamPrimary)
                    }
                    .accessibilityLabel("Edit profile")
                }

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
    }

    // MARK: - Bio

    /// The dreamer's bio, shown only once they've written one. Editing lives in
    /// the header's Edit Profile icon.
    @ViewBuilder
    private var bioCard: some View {
        if let bio = auth.bio, !bio.isEmpty {
            Text(bio)
                .font(.dreamBody(15))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DreamMetric.lg)
                .dreamCard()
        }
    }

    // MARK: - Progress

    /// The rank shown here always matches the Progress screen — both go through
    /// `DreamStore.totalXP`.
    private var totalXP: Int {
        store.totalXP(
            dreams: dreams,
            lucidSections: lucidSectionsCompleted,
            questBankedXP: questBankedXP
        )
    }

    private var level: Int { DreamProgression.level(forXP: totalXP) }
    private var rank: DreamProgression.Rank { DreamProgression.rank(forLevel: level) }

    /// A compact rank badge for the profile header.
    private var rankBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 10, weight: .bold))
            Text(localized(rank.name))
                .font(.dreamBody(12, .bold))
        }
        .foregroundStyle(Color.dreamPrimary)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color.dreamPrimary.opacity(0.14), in: .capsule)
    }

    /// Entry point to the full Progress screen (level, quests, streak, badges,
    /// activity), which now lives under the Profile tab instead of its own.
    private var progressCard: some View {
        Button {
            SoundManager.shared.play(.tap)
            showingProgress = true
        } label: {
            HStack(spacing: DreamMetric.md) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.dreamPrimary)
                    .frame(width: 44, height: 44)
                    .background(Color.dreamPrimary.opacity(0.12), in: .circle)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Progress & Achievements")
                        .font(.dreamCardTitle)
                    Text("Level \(level) · \(localized(rank.name))")
                        .font(.dreamSubtext)
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

    /// Honor a pending request (e.g. from the Home quests shortcut) to open the
    /// Progress screen, then clear it. Deferred so the push lands cleanly.
    private func consumeProgressIntent() {
        guard router.openProgress else { return }
        router.openProgress = false
        DispatchQueue.main.async { showingProgress = true }
    }

    // MARK: - Profile photo

    private var avatar: some View {
        PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
            ZStack {
                if let profileImage {
                    profileImage
                        .resizable()
                        .scaledToFill()
                } else {
                    LinearGradient(
                        colors: [.dreamPrimary, .dreamAccent],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    Text(initials)
                        .font(.dreamSerif(26))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.dreamText.opacity(0.1), lineWidth: 1))
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(Color.dreamPrimary, in: .circle)
                    .overlay(Circle().stroke(Color.dreamBase, lineWidth: 2))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Change profile photo")
        .contextMenu {
            if let data = profilePhotoData {
                Button {
                    cropItem = CropItem(data: data)
                } label: {
                    Label("Adjust Photo", systemImage: "crop")
                }
                Button(role: .destructive) {
                    profilePhotoData = nil
                    photoItem = nil
                } label: {
                    Label("Remove Photo", systemImage: "trash")
                }
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await prepareCrop(item) }
        }
        // Sync the photo to the account so it follows the dreamer across devices
        // (covers setting, re-cropping, and removing).
        .onChange(of: profilePhotoData) { _, newValue in
            Task { await auth.updateAvatar(newValue) }
        }
    }

    /// The stored profile photo as a SwiftUI `Image`, if one is set.
    private var profileImage: Image? {
        #if canImport(UIKit)
        if let data = profilePhotoData, let uiImage = UIImage(data: data) {
            return Image(uiImage: uiImage)
        }
        #endif
        return nil
    }

    /// Up to two initials from the dreamer's name, for the placeholder avatar.
    private var initials: String {
        let parts = userName
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first.map(String.init) }
        let joined = parts.joined().uppercased()
        return joined.isEmpty ? "🌙" : joined
    }

    /// Load the picked photo's data and hand it to the cropper.
    private func prepareCrop(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        #if canImport(UIKit)
        cropItem = CropItem(data: data)
        #else
        // No cropper without UIKit — store as-is.
        profilePhotoData = data
        SoundManager.shared.play(.shimmer)
        #endif
        photoItem = nil
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
                    .font(.dreamSectionHeader)
            }

            if topThemes.isEmpty {
                Text(dreams.isEmpty
                     ? "Record a dream to see themes."
                     : "Analyze your dreams with AI to surface their themes.")
                    .font(.dreamBodyText)
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
        // Once signed in there's nothing to prompt — hide the card entirely.
        if !auth.isSignedIn {
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
                            .font(.dreamCardTitle)
                        Text("Back up and sync your dreams")
                            .font(.dreamSubtext)
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

/// The AI-surfaced themes across the given dreams, deduped case-insensitively and
/// counted once per dream, ranked by frequency (ties broken alphabetically). Used
/// by both the Profile top-5 list and the full list.
func rankedDreamThemes(from dreams: [Dream]) -> [(name: String, count: Int)] {
    var counts: [String: (name: String, count: Int)] = [:]
    for dream in dreams {
        var seen = Set<String>()
        for raw in dream.aiThemes {
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
        // Normalize display casing so AI themes never render in ALL CAPS.
        .map { ($0.name.capitalized, $0.count) }
}

/// A just-picked photo's raw data, awaiting crop. Identifiable so it can drive a
/// `fullScreenCover(item:)`.
struct CropItem: Identifiable {
    let id = UUID()
    let data: Data
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
                        .font(.dreamBodyText)
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
            dream.aiThemes.contains { $0.caseInsensitiveCompare(theme) == .orderedSame }
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
        .environment(PreviewData.store)
        .environment(AppRouter())
        .environment(AuthService())
        .environment(SubscriptionManager())
}

#Preview("Dark") {
    ProfileView()
        .modelContainer(PreviewData.container)
        .environment(PreviewData.store)
        .environment(AppRouter())
        .environment(AuthService())
        .environment(SubscriptionManager())
        .preferredColorScheme(.dark)
}
