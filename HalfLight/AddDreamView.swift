//
//  AddDreamView.swift
//  HalfLight
//
//  A form for capturing a new dream or editing an existing one.
//

import SwiftUI

struct AddDreamView: View {
    /// The dream being edited, or `nil` when creating a new one.
    var existingDream: Dream?
    /// Called with the captured values when the user taps Save.
    let onSave: (DreamDraft) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var entry: String
    @State private var mood: Dream.Mood
    @State private var tagText: String

    init(existingDream: Dream? = nil, onSave: @escaping (DreamDraft) -> Void) {
        self.existingDream = existingDream
        self.onSave = onSave
        _title = State(initialValue: existingDream?.title ?? "")
        _entry = State(initialValue: existingDream?.entry ?? "")
        _mood = State(initialValue: existingDream?.mood ?? .vivid)
        _tagText = State(initialValue: existingDream?.tags.joined(separator: ", ") ?? "")
    }

    private var isEditing: Bool { existingDream != nil }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !entry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Give your dream a name", text: $title)
                }

                Section("What happened?") {
                    TextField(
                        "Describe the dream while it's still fresh…",
                        text: $entry,
                        axis: .vertical
                    )
                    .lineLimit(4...10)
                }

                Section("Mood") {
                    Picker("Mood", selection: $mood) {
                        ForEach(Dream.Mood.allCases) { mood in
                            Label(mood.rawValue, systemImage: mood.symbol)
                                .tag(mood)
                        }
                    }
                    #if os(iOS)
                    .pickerStyle(.navigationLink)
                    #endif
                }

                Section("Tags") {
                    TextField("Comma-separated, e.g. ocean, flight", text: $tagText)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                }
            }
            .navigationTitle(isEditing ? "Edit Dream" : "New Dream")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        let tags = tagText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let draft = DreamDraft(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            entry: entry.trimmingCharacters(in: .whitespacesAndNewlines),
            mood: mood,
            tags: tags
        )
        onSave(draft)
        dismiss()
    }
}

#Preview("New") {
    AddDreamView { _ in }
}

#Preview("Edit") {
    AddDreamView(existingDream: Dream.preview) { _ in }
}
