//
//  DreamJournalView.swift
//  HalfLight
//
//  The dream library: a scrollable list of recorded dreams.
//

import SwiftUI
import SwiftData

struct DreamJournalView: View {
    @Query(sort: \Dream.date, order: .reverse) private var dreams: [Dream]
    @Environment(DreamStore.self) private var store
    @State private var isAddingDream = false

    var body: some View {
        NavigationStack {
            Group {
                if dreams.isEmpty {
                    emptyState
                } else {
                    library
                }
            }
            .background { DreamBackground() }
            .navigationTitle("Dream Journal")
            .fullScreenCover(isPresented: $isAddingDream) {
                AddDreamView { draft in
                    store.add(draft)
                }
            }
        }
    }

    // MARK: - Library

    private var library: some View {
        List {
            ForEach(dreams) { dream in
                NavigationLink {
                    DreamDetailView(dream: dream)
                } label: {
                    DreamCard(dream: dream)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            .onDelete { offsets in
                for index in offsets {
                    store.delete(dreams[index])
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Dreams Yet", systemImage: "moon.stars")
        } description: {
            Text("Capture your first dream before it fades.")
        } actions: {
            Button {
                isAddingDream = true
            } label: {
                Text("Add a Dream")
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
        }
    }
}

/// A single dream rendered as a card in the library.
struct DreamCard: View {
    let dream: Dream

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label {
                    Text(dream.mood.rawValue)
                        .font(.caption.weight(.semibold))
                } icon: {
                    Image(systemName: dream.mood.symbol)
                }
                .foregroundStyle(dream.mood.tint)

                Spacer()

                Text(dream.date, format: .dateTime.month().day().hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(dream.title)
                .font(.title3.weight(.semibold))

            Text(dream.entry)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            if !dream.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(dream.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(dream.mood.tint.opacity(0.18), in: .capsule)
                                .foregroundStyle(dream.mood.tint)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dreamSurface, in: .rect(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(dream.mood.tint.opacity(0.25), lineWidth: 1)
        )
    }
}

#Preview {
    DreamJournalView()
        .modelContainer(PreviewData.container)
        .environment(PreviewData.store)
}
