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
    @State private var showDeleteConfirm = false

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

                deleteButton
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
                Button("Edit") { isEditing = true }
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
        .confirmationDialog(
            "Delete this dream?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                dismiss()
                store.delete(dream)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            showDeleteConfirm = true
        } label: {
            Label("Delete Dream", systemImage: "trash")
                .font(.dreamBody(15, .semibold))
                .frame(maxWidth: .infinity)
        }
        .padding(.top, 8)
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
        Task {
            guard let result = await analyzer.analyze(
                title: dream.title,
                entry: dream.entry,
                mood: dream.mood.rawValue
            ) else { return }
            store.setAnalysis(dream, category: result.category, meaning: result.meaning)
        }
    }

    // MARK: - Tags

    private var tagCloud: some View {
        VStack(alignment: .leading, spacing: DreamMetric.sm) {
            Text("Themes")
                .font(.dreamSectionHeader)
            FlowTags(tags: dream.tags, tint: dream.mood.tint)
        }
    }
}

/// A simple wrapping row of tag chips.
private struct FlowTags: View {
    let tags: [String]
    let tint: Color

    var body: some View {
        ViewThatFits(in: .horizontal) {
            chips
            ScrollView(.horizontal, showsIndicators: false) { chips }
        }
    }

    private var chips: some View {
        HStack(spacing: 8) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.dreamBody(12, .semibold))
                    .padding(.horizontal, DreamMetric.md)
                    .padding(.vertical, DreamMetric.xs + 2)
                    .background(tint.opacity(0.18), in: .capsule)
                    .foregroundStyle(tint)
            }
        }
    }
}

#Preview("Light") {
    NavigationStack {
        DreamDetailView(dream: Dream.preview)
    }
    .modelContainer(PreviewData.container)
    .environment(PreviewData.store)
}

#Preview("Dark") {
    NavigationStack {
        DreamDetailView(dream: Dream.preview)
    }
    .modelContainer(PreviewData.container)
    .environment(PreviewData.store)
    .preferredColorScheme(.dark)
}
