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
    @State private var isEditing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                Text(dream.entry)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !dream.tags.isEmpty {
                    tagCloud
                }
            }
            .padding(20)
        }
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
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text(dream.mood.rawValue)
                    .font(.subheadline.weight(.semibold))
            } icon: {
                Image(systemName: dream.mood.symbol)
            }
            .foregroundStyle(dream.mood.tint)

            Text(dream.title)
                .font(.largeTitle.weight(.bold))

            Text(dream.date, format: .dateTime.weekday(.wide).month().day().hour().minute())
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Tags

    private var tagCloud: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Themes")
                .font(.headline)
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
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
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
