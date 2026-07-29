//
//  DreamDetailView.swift
//  HalfLight
//
//  Full-screen view of a single dream, with editing.
//

import SwiftUI
import SwiftData

struct DreamDetailView: View {
    let dream: Dream
    /// The author, when this dream was opened from the feed — drives the tappable
    /// author header. `nil` from the journal/profile (it's your own dream there).
    var feedAuthor: FeedAuthor? = nil
    /// When the dream was posted to the feed, shown beside the author's handle.
    var postedAt: Date? = nil

    @Environment(DreamStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(SubscriptionManager.self) private var subscriptions
    @State private var isEditing = false
    @State private var analyzer = DreamAnalyzer()
    /// The author profile to push when the header is tapped.
    @State private var profileToOpen: FeedAuthor?
    /// Presented when a non-subscriber taps Analyze with AI.
    @State private var showPaywall = false
    /// Set when the paywall was opened by a tap on Analyze, so subscribing runs
    /// the analysis right away instead of dropping the tap.
    @State private var analyzeAfterPaywall = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if feedAuthor != nil {
                    authorHeader
                }

                header

                Text(dream.entry)
                    .font(.dreamBody(16))
                    .lineSpacing(5)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !dream.tags.isEmpty {
                    tagCloud
                }

                aiSection
            }
            .padding(20)
        }
        .tabBarClearance()
        .background { DreamBackground() }
        .navigationTitle(dream.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .navigationDestination(item: $profileToOpen) { author in
            PublicProfileView(author: author)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        SoundManager.shared.play(.tap)
                        isEditing = true
                    } label: {
                        Label("Edit", systemImage: "square.and.pencil")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .fullScreenCover(isPresented: $isEditing) {
            AddDreamView(existingDream: dream) { draft in
                store.update(dream, with: draft)
            } onDelete: {
                dismiss()
                store.delete(dream)
            }
        }
        .sheet(isPresented: $showPaywall, onDismiss: resumeAnalyzeAfterPaywall) { PaywallView() }
        .task {
            // A brand-new subscription can beat its own record to the server; let
            // the analyzer push it across and retry rather than telling a paying
            // dreamer to subscribe.
            analyzer.recoverEntitlement = { await subscriptions.ensureServerEntitlement() }
        }
    }

    // MARK: - Author (feed only)

    /// Tappable author card: photo, name, @handle, and when it was posted. The
    /// whole row opens the author's profile.
    @ViewBuilder
    private var authorHeader: some View {
        if let feedAuthor {
            Button {
                SoundManager.shared.play(.tap)
                profileToOpen = feedAuthor
            } label: {
                HStack(spacing: DreamMetric.md) {
                    FeedAvatar(photoData: feedAuthor.photo, name: feedAuthor.name, size: 44)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(feedAuthor.name)
                            .font(.dreamBody(15, .semibold))
                            .foregroundStyle(Color.dreamText)
                        HStack(spacing: 4) {
                            Text("@\(feedAuthor.username)")
                                .foregroundStyle(Color.dreamPrimary)
                            if let postedAt {
                                Text("·")
                                    .foregroundStyle(.secondary)
                                Text(postedAt, format: .relative(presentation: .named))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.dreamCaption)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.dreamCaption)
                        .foregroundStyle(.secondary)
                }
                .padding(DreamMetric.md)
                .dreamCard()
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: DreamMetric.sm) {
            Label {
                Text(localized(dream.mood.rawValue))
                    .font(.dreamBody(14, .semibold))
            } icon: {
                Image(systemName: dream.mood.symbol)
            }
            .foregroundStyle(dream.mood.tint)

            Text(dream.title)
                .font(.dreamDisplay(30))

            Text(dream.date, format: .dateTime.weekday(.wide).month().day().hour().minute())
                .font(.dreamSubtext)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - AI analysis

    @ViewBuilder
    private var aiSection: some View {
        if let category = dream.aiCategory, let meaning = dream.aiMeaning {
            VStack(alignment: .leading, spacing: DreamMetric.md) {
                HStack(spacing: DreamMetric.sm) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Color.dreamPrimary)
                    Text("AI Insight")
                        .font(.dreamCardTitle)
                }

                Text(category)
                    .font(.dreamCaption)
                    .padding(.horizontal, DreamMetric.md)
                    .padding(.vertical, DreamMetric.xs + 2)
                    .background(Color.dreamPrimary.opacity(0.18), in: .capsule)
                    .foregroundStyle(Color.dreamPrimary)

                Text(meaning)
                    .font(.dreamBodyText)
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)

                if !dream.aiThemes.isEmpty {
                    VStack(alignment: .leading, spacing: DreamMetric.sm) {
                        Text("Themes")
                            .font(.dreamBody(13, .semibold))
                            .foregroundStyle(.secondary)
                        // AI themes stay on a single line; scroll horizontally to
                        // see any that don't fit.
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(dream.aiThemes, id: \.self) { theme in
                                    Text(theme.capitalized)
                                        .font(.dreamBody(12, .semibold))
                                        .padding(.horizontal, DreamMetric.md)
                                        .padding(.vertical, DreamMetric.xs + 2)
                                        .background(Color.dreamPrimary.opacity(0.18), in: .capsule)
                                        .foregroundStyle(Color.dreamPrimary)
                                }
                            }
                        }
                    }
                    .padding(.top, DreamMetric.xs)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DreamMetric.xl)
            .dreamCard()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Button(action: analyze) {
                    HStack(spacing: 8) {
                        if analyzer.isAnalyzing {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: subscriptions.isSubscribed ? "sparkles" : "lock.fill")
                        }
                        Text(analyzer.isAnalyzing ? "Analyzing…" : "Analyze with AI")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(analyzer.isAnalyzing)

                if let error = analyzer.errorMessage {
                    Text(error)
                        .font(.dreamSubtext)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    /// Run the analysis once the paywall closes, if subscribing is what closed it.
    private func resumeAnalyzeAfterPaywall() {
        guard analyzeAfterPaywall else { return }
        analyzeAfterPaywall = false
        guard subscriptions.isSubscribed else { return }
        analyze()
    }

    private func analyze() {
        // AI analysis is HalfLight Pro: send non-subscribers to the paywall, and
        // pick this tap back up the moment they're subscribed.
        guard subscriptions.isSubscribed else {
            analyzeAfterPaywall = true
            showPaywall = true
            return
        }
        // The button's style plays the press tap; we add the result sounds below.
        Task {
            guard let result = await analyzer.analyze(
                title: dream.title,
                entry: dream.entry,
                mood: dream.mood.rawValue
            ) else {
                SoundManager.shared.play(.wrong)
                return
            }
            store.setAnalysis(
                dream,
                category: result.category,
                meaning: result.meaning,
                themes: result.themes ?? []
            )
            SoundManager.shared.play(.shimmer)
        }
    }

    // MARK: - Tags

    private var tagCloud: some View {
        VStack(alignment: .leading, spacing: DreamMetric.sm) {
            Text("Tags")
                .font(.dreamSectionHeader)
            FlowTags(tags: dream.tags, tint: dream.mood.tint)
        }
    }
}

/// A wrapping row of tag chips: chips that don't fit flow onto the next line
/// rather than scrolling horizontally.
private struct FlowTags: View {
    let tags: [String]
    let tint: Color

    var body: some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.dreamBody(12, .semibold))
                    .padding(.horizontal, DreamMetric.md)
                    .padding(.vertical, DreamMetric.xs + 2)
                    .background(tint.opacity(0.18), in: .capsule)
                    .foregroundStyle(tint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A left-to-right flow layout that wraps subviews onto new lines when they'd
/// overflow the available width.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }

        let width = maxWidth.isFinite ? maxWidth : x - spacing
        return CGSize(width: max(0, width), height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

#Preview("Light") {
    NavigationStack {
        DreamDetailView(dream: Dream.preview)
    }
    .modelContainer(PreviewData.container)
    .environment(PreviewData.store)
    .environment(AuthService())
    .environment(SubscriptionManager())
}

#Preview("Dark") {
    NavigationStack {
        DreamDetailView(dream: Dream.preview)
    }
    .modelContainer(PreviewData.container)
    .environment(PreviewData.store)
    .environment(AuthService())
    .environment(SubscriptionManager())
    .preferredColorScheme(.dark)
}
