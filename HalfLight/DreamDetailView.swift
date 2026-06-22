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

    @Environment(DreamStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var isEditing = false
    @State private var analyzer = DreamAnalyzer()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
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
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: DreamMetric.sm) {
            Label {
                Text(dream.mood.rawValue)
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
                            Image(systemName: "sparkles")
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

    private func analyze() {
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
}

#Preview("Dark") {
    NavigationStack {
        DreamDetailView(dream: Dream.preview)
    }
    .modelContainer(PreviewData.container)
    .environment(PreviewData.store)
    .environment(AuthService())
    .preferredColorScheme(.dark)
}
