//
//  FeedPostCard.swift
//  HalfLight
//
//  One dream as it appears in the social feed: the author's photo + @handle, the
//  dream title and description, and a comment / like row along the bottom.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct FeedPostCard: View {
    let post: FeedPost
    /// The source dream, when it lives locally — drives the mood, AI insight, and
    /// tags. `nil` falls back to the post's own title/description snapshot.
    var dream: Dream?
    /// The author's profile photo resolved by @handle (fetched from their profile).
    /// Falls back to the snapshot captured on the post when not provided — see
    /// `displayPhoto`.
    var resolvedPhoto: Data? = nil
    /// Open the full dream. Fired by tapping the card outside the action buttons.
    var onOpen: () -> Void = {}
    /// Open the author's profile. Fired by tapping their photo, name, or handle.
    var onOpenProfile: () -> Void = {}
    /// Toggle the like state. Owned by the feed so it can persist the change.
    var onToggleLike: () -> Void = {}
    /// Open the comments for this post. A no-op until comments are built out.
    var onComment: () -> Void = {}
    /// Report this dream. Fired from the card's long-press context menu.
    var onReport: () -> Void = {}
    /// Block this dream's author. Fired from the card's long-press context menu.
    var onBlock: () -> Void = {}
    /// Record that this card was shown (one impression). Drives the conversion rate.
    var onImpression: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: DreamMetric.lg) {
            authorRow

            VStack(alignment: .leading, spacing: DreamMetric.md) {
                if let mood = displayMood {
                    feelingRow(mood: mood, tags: displayTags)
                        // Drop the feeling row below the mood orb in the corner.
                        .padding(.top, DreamMetric.sm)
                }

                Text(post.title)
                    .font(.dreamDisplay(28))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Keep the title clear of the mood orb in the top corner.
                    .padding(.trailing, displayMood == nil ? 0 : 64)

                Text(post.dreamDescription)
                    .font(.dreamBodyText)
                    .foregroundStyle(.secondary)
                    .lineSpacing(5)
                    // When analyzed, hand most of the room to the AI insight below.
                    .lineLimit(isAnalyzed ? 4 : 12)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let insight = aiInsight {
                    aiInsightView(insight)
                }

                if !aiThemeChips.isEmpty {
                    aiThemeRow
                }
            }
            // Fill the space between the author row and the actions so the AI
            // insight can stretch toward the bottom of the page.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            Divider()
                .overlay(Color.dreamText.opacity(0.08))

            actionRow
        }
        .padding(DreamMetric.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .dreamCard()
        .overlay(alignment: .topTrailing) { moodOrb }
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .contextMenu {
            Button {
                SoundManager.shared.play(.tap)
                onReport()
            } label: {
                Label("Report Dream", systemImage: "flag")
            }
            Button(role: .destructive) {
                SoundManager.shared.play(.tap)
                onBlock()
            } label: {
                Label("Block @\(post.authorUsername)", systemImage: "hand.raised.slash")
            }
        }
        .onAppear(perform: onImpression)
    }

    // MARK: - Feeling + user tags

    /// The mood ("feeling") followed by the dreamer's own tags, on one scrolling
    /// line. AI themes (when present) live lower down in their own row.
    /// The mood to render: the live local dream's, or the post's snapshot so
    /// other dreamers see the feeling label, tag tint, and corner orb too.
    private var displayMood: Dream.Mood? {
        if let mood = dream?.mood { return mood }
        if let raw = post.mood { return Dream.Mood(rawValue: raw) }
        return nil
    }

    /// The dreamer's own tags: live from the local dream, else the post snapshot.
    private var displayTags: [String] {
        dream?.tags ?? post.tags
    }

    private func feelingRow(mood: Dream.Mood, tags: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DreamMetric.sm) {
                moodLabel(mood)

                ForEach(tags, id: \.self) { tag in
                    tagChip(tag, tint: mood.tint)
                }
            }
            // Stay clear of the mood orb in the top corner.
            .padding(.trailing, 64)
        }
    }

    private func moodLabel(_ mood: Dream.Mood) -> some View {
        Label {
            Text(localized(mood.rawValue)).font(.dreamBody(13, .semibold))
        } icon: {
            Image(systemName: mood.symbol)
        }
        .foregroundStyle(mood.tint)
    }

    /// The glowing orb in the top corner, colored by the dream's mood. Decorative,
    /// so it never intercepts the card's tap.
    @ViewBuilder
    private var moodOrb: some View {
        if let mood = displayMood {
            MoodOrb(tint: mood.tint, diameter: 56)
                .padding(.top, DreamMetric.md)
                .padding(.trailing, DreamMetric.md)
                .allowsHitTesting(false)
        }
    }

    // MARK: - AI insight

    /// Whether there's a completed AI analysis to show — from the local dream
    /// (the author's own card) or, failing that, the snapshot on the post (so
    /// other dreamers see it too).
    private var isAnalyzed: Bool {
        aiInsight != nil
    }

    /// The AI category + meaning. Prefers the live local dream, then the post's
    /// snapshot, so the insight shows even when the source dream isn't on-device.
    private var aiInsight: (category: String, meaning: String)? {
        if let category = dream?.aiCategory, let meaning = dream?.aiMeaning {
            return (category, meaning)
        }
        if let category = post.aiCategory, let meaning = post.aiMeaning {
            return (category, meaning)
        }
        return nil
    }

    private func aiInsightView(_ insight: (category: String, meaning: String)) -> some View {
        VStack(alignment: .leading, spacing: DreamMetric.sm) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                Text("AI Insight")
                    .font(.dreamBody(13, .semibold))
                Text(insight.category)
                    .font(.dreamBody(11, .semibold))
                    .padding(.horizontal, DreamMetric.sm)
                    .padding(.vertical, 3)
                    .background(Color.dreamPrimary.opacity(0.18), in: .capsule)
            }
            .foregroundStyle(Color.dreamPrimary)

            // No line limit: let the interpretation run on and fill the card down
            // toward the actions, truncating only if it would overflow the page.
            Text(insight.meaning)
                .font(.dreamBody(14))
                .foregroundStyle(.secondary)
                .lineSpacing(5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(DreamMetric.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.dreamPrimary.opacity(0.06), in: .rect(cornerRadius: DreamMetric.cardRadius))
    }

    // MARK: - AI theme tags

    /// The AI-surfaced themes, shown only once the dream has been analyzed. (The
    /// dreamer's own tags sit next to the feeling instead — see `feelingRow`.)
    private var aiThemeChips: [String] {
        let fromDream = dream?.aiThemes ?? []
        let themes = fromDream.isEmpty ? post.aiThemes : fromDream
        guard isAnalyzed, !themes.isEmpty else { return [] }
        return themes.map(\.capitalized)
    }

    private var aiThemeRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(aiThemeChips, id: \.self) { chip in
                    tagChip(chip, tint: .dreamPrimary)
                }
            }
        }
    }

    private func tagChip(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.dreamBody(12, .semibold))
            .padding(.horizontal, DreamMetric.md)
            .padding(.vertical, DreamMetric.xs + 2)
            .background(tint.opacity(0.18), in: .capsule)
            .foregroundStyle(tint)
    }

    // MARK: - Author

    /// The author's profile photo: the freshly resolved one when supplied, else the
    /// snapshot stored on the post (kept current for your own posts; `nil` for other
    /// dreamers, who then fall back to initials until their avatar is fetched).
    private var displayPhoto: Data? {
        post.authorPhoto ?? resolvedPhoto
    }

    private var authorRow: some View {
        HStack(spacing: DreamMetric.md) {
            // The photo, name, and handle together open the author's profile.
            Button {
                SoundManager.shared.play(.tap)
                onOpenProfile()
            } label: {
                HStack(spacing: DreamMetric.md) {
                    FeedAvatar(photoData: displayPhoto, name: post.authorName, size: 40)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(post.authorName)
                            .font(.dreamBody(14, .semibold))
                            .foregroundStyle(Color.dreamText)
                        HStack(spacing: 4) {
                            Text("@\(post.authorUsername)")
                                .foregroundStyle(Color.dreamPrimary)
                            Text("·")
                                .foregroundStyle(.secondary)
                            Text(post.createdAt, format: .relative(presentation: .named))
                                .foregroundStyle(.secondary)
                        }
                        .font(.dreamCaption)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
        }
    }

    // MARK: - Comment / like

    private var actionRow: some View {
        HStack(spacing: DreamMetric.xl) {
            Button {
                SoundManager.shared.play(.tap)
                onComment()
            } label: {
                actionLabel(symbol: "bubble.left", count: post.commentCount, active: false)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Comment")

            Spacer(minLength: 0)

            Button {
                SoundManager.shared.play(post.isLiked ? .tap : .shimmer)
                onToggleLike()
            } label: {
                actionLabel(
                    symbol: post.isLiked ? "heart.fill" : "heart",
                    count: post.likeCount,
                    active: post.isLiked
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(post.isLiked ? "Unlike" : "Like")
        }
    }

    private func actionLabel(symbol: String, count: Int, active: Bool) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
            if count > 0 {
                Text("\(count)")
                    .font(.dreamBody(15, .semibold))
            }
        }
        .foregroundStyle(active ? Color.dreamAccent : Color.dreamText.opacity(0.6))
        .contentTransition(.symbolEffect(.replace))
    }
}

/// A circular avatar that shows a profile photo when present, otherwise the
/// author's initials over the app gradient. Mirrors the Profile header avatar.
struct FeedAvatar: View {
    let photoData: Data?
    let name: String
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            if let image {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [.dreamPrimary, .dreamAccent],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                Text(initials)
                    .font(.dreamSerif(size * 0.4))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.dreamText.opacity(0.1), lineWidth: 1))
    }

    private var image: Image? {
        #if canImport(UIKit)
        if let photoData, let uiImage = AvatarImageCache.image(for: photoData) {
            return Image(uiImage: uiImage)
        }
        #endif
        return nil
    }

    private var initials: String {
        let parts = name
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first.map(String.init) }
        let joined = parts.joined().uppercased()
        return joined.isEmpty ? "🌙" : joined
    }
}

#Preview("Analyzed") {
    let dream = Dream(
        title: "The Floating Library",
        entry: "I wandered through a library where the books drifted off the shelves.",
        date: .now,
        mood: .vivid,
        tags: ["memory", "flight"],
        aiCategory: "Symbolic",
        aiMeaning: "A search for forgotten knowledge — the rearranging staircases suggest a mind reordering its own past to find a way forward.",
        aiThemes: ["Memory", "Discovery", "Flight"]
    )
    return FeedPostCard(
        post: FeedPost(
            dreamID: dream.id,
            authorUsername: "lucid_wanderer",
            authorName: "Ryan Lewandowski",
            title: dream.title,
            dreamDescription: "I wandered through a library where the books drifted off the shelves and rearranged themselves into staircases. Each step I climbed revealed a new memory I'd forgotten.",
            likeCount: 12,
            isLiked: true,
            commentCount: 3
        ),
        dream: dream
    )
    .padding()
    .background(Color.dreamBase)
}

#Preview("Not analyzed") {
    let dream = Dream(
        title: "Tide of Strangers",
        entry: "A crowd of faceless people moved like a tide along a shoreline.",
        date: .now,
        mood: .strange,
        tags: ["crowds", "ocean", "identity"]
    )
    return FeedPostCard(
        post: FeedPost(
            dreamID: dream.id,
            authorUsername: "tidewalker",
            authorName: "Sam Rivers",
            title: dream.title,
            dreamDescription: "A crowd of faceless people moved like a tide along a shoreline. They were calm, and somehow I knew all of their names.",
            likeCount: 4,
            commentCount: 1
        ),
        dream: dream
    )
    .padding()
    .background(Color.dreamBase)
}
