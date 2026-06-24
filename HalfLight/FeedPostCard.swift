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
    /// Open the full dream. Fired by tapping the card outside the action buttons.
    var onOpen: () -> Void = {}
    /// Open the author's profile. Fired by tapping their photo, name, or handle.
    var onOpenProfile: () -> Void = {}
    /// Toggle the like state. Owned by the feed so it can persist the change.
    var onToggleLike: () -> Void = {}
    /// Open the comments for this post. A no-op until comments are built out.
    var onComment: () -> Void = {}
    /// Record that this card was shown (one impression). Drives the conversion rate.
    var onImpression: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: DreamMetric.lg) {
            authorRow

            VStack(alignment: .leading, spacing: DreamMetric.md) {
                if let dream {
                    feelingRow(dream)
                        // Drop the feeling row below the mood orb in the corner.
                        .padding(.top, DreamMetric.sm)
                }

                Text(post.title)
                    .font(.dreamDisplay(28))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Keep the title clear of the mood orb in the top corner.
                    .padding(.trailing, dream == nil ? 0 : 64)

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
        .onAppear(perform: onImpression)
    }

    // MARK: - Feeling + user tags

    /// The mood ("feeling") followed by the dreamer's own tags, on one scrolling
    /// line. AI themes (when present) live lower down in their own row.
    private func feelingRow(_ dream: Dream) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DreamMetric.sm) {
                moodLabel(dream.mood)

                ForEach(dream.tags, id: \.self) { tag in
                    tagChip(tag, tint: dream.mood.tint)
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
        if let mood = dream?.mood {
            MoodOrb(tint: mood.tint, diameter: 56)
                .padding(.top, DreamMetric.md)
                .padding(.trailing, DreamMetric.md)
                .allowsHitTesting(false)
        }
    }

    // MARK: - AI insight

    /// Whether the source dream has a completed AI analysis.
    private var isAnalyzed: Bool {
        dream?.aiCategory != nil && dream?.aiMeaning != nil
    }

    /// The AI category + meaning, present only once the dream has been analyzed.
    private var aiInsight: (category: String, meaning: String)? {
        guard let dream, let category = dream.aiCategory, let meaning = dream.aiMeaning else {
            return nil
        }
        return (category, meaning)
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
        guard isAnalyzed, let themes = dream?.aiThemes, !themes.isEmpty else { return [] }
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

    private var authorRow: some View {
        HStack(spacing: DreamMetric.md) {
            // The photo, name, and handle together open the author's profile.
            Button {
                SoundManager.shared.play(.tap)
                onOpenProfile()
            } label: {
                HStack(spacing: DreamMetric.md) {
                    FeedAvatar(photoData: post.authorPhoto, name: post.authorName, size: 40)

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

            Spacer(minLength: 0)
        }
    }

    private func actionLabel(symbol: String, count: Int, active: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
            if count > 0 {
                Text("\(count)")
                    .font(.dreamBody(13, .semibold))
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
        if let photoData, let uiImage = UIImage(data: photoData) {
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
