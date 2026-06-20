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
    /// Set right after a new dream is saved; pushes its detail view so the user
    /// can immediately analyze it with AI.
    @State private var newDream: Dream?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 12)

                Group {
                    if dreams.isEmpty {
                        emptyState
                    } else {
                        library
                    }
                }
            }
            .background { DreamBackground() }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $newDream) { dream in
                DreamDetailView(dream: dream)
            }
            .fullScreenCover(isPresented: $isAddingDream) {
                AddDreamView { draft in
                    newDream = store.add(draft)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("Journal")
                .font(.dreamTitle)
            Spacer()
            Button {
                isAddingDream = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.dreamPrimary)
            }
            .accessibilityLabel("Add Dream")
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
        .tabBarClearance()
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
        VStack(alignment: .leading, spacing: DreamMetric.sm) {
            HStack {
                Label {
                    Text(dream.mood.rawValue)
                        .font(.dreamCaption)
                } icon: {
                    Image(systemName: dream.mood.symbol)
                }
                .foregroundStyle(dream.mood.tint)

                Spacer()

                Text(dream.date, format: .dateTime.month().day().hour().minute())
                    .font(.dreamBody(12, .medium))
                    .foregroundStyle(.secondary)
            }

            Text(dream.title)
                .font(.dreamCardTitle)
                .lineLimit(2)

            Text(dream.entry)
                .font(.dreamSubtext)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .lineLimit(3)

            if !dream.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DreamMetric.sm) {
                        ForEach(dream.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.dreamBody(12, .semibold))
                                .padding(.horizontal, DreamMetric.md)
                                .padding(.vertical, DreamMetric.xs)
                                .background(dream.mood.tint.opacity(0.18), in: .capsule)
                                .foregroundStyle(dream.mood.tint)
                        }
                    }
                }
            }
        }
        .padding(DreamMetric.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dreamSurface, in: .rect(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(dream.mood.tint.opacity(0.25), lineWidth: 1)
        )
    }
}

#Preview("Light") {
    DreamJournalView()
        .modelContainer(PreviewData.container)
        .environment(PreviewData.store)
}

#Preview("Dark") {
    DreamJournalView()
        .modelContainer(PreviewData.container)
        .environment(PreviewData.store)
        .preferredColorScheme(.dark)
}
