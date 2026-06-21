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
    /// Called when the user deletes the dream while editing. `nil` hides the
    /// delete option (e.g. when creating a new dream).
    var onDelete: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirm = false

    @State private var title: String
    @State private var entry: String
    @State private var mood: Dream.Mood
    @State private var tagText: String

    // AI analysis captured in-form, so a dream can be interpreted before it's saved.
    @State private var aiCategory: String?
    @State private var aiMeaning: String?
    @State private var aiThemes: [String]

    @AppStorage("appTheme") private var theme: AppTheme = .system
    @State private var transcriber = DreamTranscriber()
    @State private var entryBeforeDictation = ""
    @State private var analyzer = DreamAnalyzer()

    init(
        existingDream: Dream? = nil,
        onSave: @escaping (DreamDraft) -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        self.existingDream = existingDream
        self.onSave = onSave
        self.onDelete = onDelete
        _title = State(initialValue: existingDream?.title ?? "")
        _entry = State(initialValue: existingDream?.entry ?? "")
        _mood = State(initialValue: existingDream?.mood ?? .vivid)
        _tagText = State(initialValue: existingDream?.tags.joined(separator: ", ") ?? "")
        _aiCategory = State(initialValue: existingDream?.aiCategory)
        _aiMeaning = State(initialValue: existingDream?.aiMeaning)
        _aiThemes = State(initialValue: existingDream?.aiThemes ?? [])
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
                    HStack {
                        TextField("Give your dream a name", text: $title)
                        if !title.isEmpty {
                            Button {
                                title = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Clear title")
                        }
                    }
                }
                .listRowBackground(Color.dreamSurface)

                Section("What happened?") {
                    TextField(
                        "Describe the dream while it's still fresh…",
                        text: $entry,
                        axis: .vertical
                    )
                    .lineLimit(4...10)

                    dictationControl
                }
                .listRowBackground(Color.dreamSurface)

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
                .listRowBackground(Color.dreamSurface)

                Section("Tags") {
                    TextField("Comma-separated, e.g. ocean, flight", text: $tagText)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif

                    autoTagControl
                }
                .listRowBackground(Color.dreamSurface)

                Section("AI Insight") {
                    aiInsightControl
                }
                .listRowBackground(Color.dreamSurface)

                if isEditing, onDelete != nil {
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete Dream", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .listRowBackground(Color.dreamSurface)
                }
            }
            .scrollContentBackground(.hidden)
            .background { DreamBackground() }
            .confirmationDialog(
                "Delete this dream?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    transcriber.stop()
                    dismiss()
                    onDelete?()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This can't be undone.")
            }
            .onChange(of: transcriber.transcript) { _, newValue in
                applyTranscript(newValue)
            }
            .onDisappear { transcriber.stop() }
            .navigationTitle(isEditing ? "Edit Dream" : "New Dream")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        transcriber.stop()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
        }
        .tint(.dreamPrimary)
        .preferredColorScheme(theme.colorScheme)
    }

    private func save() {
        // A new dream that earns XP triggers the reward sound; this tap covers
        // edits (and is harmlessly replaced by the reward when one follows).
        SoundManager.shared.play(.tap)
        transcriber.stop()
        let tags = tagText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let draft = DreamDraft(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            entry: entry.trimmingCharacters(in: .whitespacesAndNewlines),
            mood: mood,
            tags: tags,
            aiCategory: aiMeaning == nil ? nil : aiCategory,
            aiMeaning: aiMeaning,
            aiThemes: aiMeaning == nil ? [] : aiThemes
        )
        onSave(draft)
        dismiss()
    }

    // MARK: - Auto-tag

    /// Auto-tagging draws from the dream description, so it needs entry text.
    private var canAutoTag: Bool {
        !entry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var autoTagControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: autoTag) {
                Label {
                    Text(analyzer.isSuggestingTags ? "Generating tags…" : "Auto-tag with AI")
                } icon: {
                    if analyzer.isSuggestingTags {
                        ProgressView()
                    } else {
                        Image(systemName: "sparkles")
                    }
                }
                .font(.dreamBody(15, .semibold))
                .foregroundStyle(canAutoTag ? Color.dreamPrimary : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(!canAutoTag || analyzer.isSuggestingTags)

            if let error = analyzer.errorMessage {
                Text(error)
                    .font(.dreamCaption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func autoTag() {
        SoundManager.shared.play(.tap)
        Task {
            guard let suggested = await analyzer.suggestTags(
                title: title,
                entry: entry,
                mood: mood.rawValue
            ) else {
                SoundManager.shared.play(.wrong)
                return
            }
            mergeTags(suggested)
            SoundManager.shared.play(.shimmer)
        }
    }

    /// Append AI tags to whatever the user already typed, skipping duplicates.
    private func mergeTags(_ suggested: [String]) {
        var tags = tagText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let existing = Set(tags.map { $0.lowercased() })
        for tag in suggested where !existing.contains(tag.lowercased()) {
            tags.append(tag)
        }
        tagText = tags.joined(separator: ", ")
    }

    // MARK: - AI insight

    /// Analysis needs something to interpret, so it requires entry text.
    private var canAnalyze: Bool {
        !entry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @ViewBuilder
    private var aiInsightControl: some View {
        if let meaning = aiMeaning {
            VStack(alignment: .leading, spacing: 10) {
                if let category = aiCategory {
                    Text(category)
                        .font(.dreamBody(12, .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Color.dreamPrimary.opacity(0.18), in: .capsule)
                        .foregroundStyle(Color.dreamPrimary)
                }

                Text(meaning)
                    .font(.dreamBody(15))
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)

                if !aiThemes.isEmpty {
                    Text(aiThemes.map(\.capitalized).joined(separator: " · "))
                        .font(.dreamBody(13, .medium))
                        .foregroundStyle(Color.dreamPrimary)
                }

                Button(action: analyze) {
                    Label(
                        analyzer.isAnalyzing ? "Re-analyzing…" : "Re-analyze",
                        systemImage: "arrow.clockwise"
                    )
                    .font(.dreamBody(14, .semibold))
                    .foregroundStyle(analyzer.isAnalyzing ? .secondary : Color.dreamPrimary)
                }
                .buttonStyle(.plain)
                .disabled(analyzer.isAnalyzing)
            }
            .padding(.vertical, 2)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Button(action: analyze) {
                    Label {
                        Text(analyzer.isAnalyzing ? "Interpreting your dream…" : "Analyze with AI")
                    } icon: {
                        if analyzer.isAnalyzing {
                            ProgressView()
                        } else {
                            Image(systemName: "sparkles")
                        }
                    }
                    .font(.dreamBody(15, .semibold))
                    .foregroundStyle(canAnalyze ? Color.dreamPrimary : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(!canAnalyze || analyzer.isAnalyzing)

                Text("Get an AI interpretation now, or skip it and analyze later.")
                    .font(.dreamCaption)
                    .foregroundStyle(.secondary)

                if let error = analyzer.errorMessage {
                    Text(error)
                        .font(.dreamCaption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func analyze() {
        SoundManager.shared.play(.tap)
        Task {
            guard let result = await analyzer.analyze(
                title: title,
                entry: entry,
                mood: mood.rawValue
            ) else {
                SoundManager.shared.play(.wrong)
                return
            }
            aiCategory = result.category
            aiMeaning = result.meaning
            aiThemes = result.themes ?? []
            SoundManager.shared.play(.shimmer)
        }
    }

    // MARK: - Dictation

    private var dictationControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: toggleDictation) {
                Label(
                    transcriber.isRecording ? "Listening… tap to stop" : "Dictate your dream",
                    systemImage: transcriber.isRecording ? "stop.circle.fill" : "mic.fill"
                )
                .font(.dreamBody(15, .semibold))
                .foregroundStyle(transcriber.isRecording ? Color.red : Color.dreamPrimary)
            }
            .buttonStyle(.plain)

            if let error = transcriber.errorMessage {
                Text(error)
                    .font(.dreamCaption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func toggleDictation() {
        SoundManager.shared.play(.tap)
        if transcriber.isRecording {
            transcriber.stop()
        } else {
            entryBeforeDictation = entry
            Task { await transcriber.start() }
        }
    }

    private func applyTranscript(_ transcript: String) {
        guard transcriber.isRecording, !transcript.isEmpty else { return }
        entry = entryBeforeDictation.isEmpty
            ? transcript
            : entryBeforeDictation + " " + transcript
    }
}

#Preview("New") {
    AddDreamView { _ in }
}

#Preview("New — Dark") {
    AddDreamView { _ in }
        .preferredColorScheme(.dark)
}

#Preview("Edit") {
    AddDreamView(existingDream: Dream.preview) { _ in }
}

#Preview("Edit — Dark") {
    AddDreamView(existingDream: Dream.preview) { _ in }
        .preferredColorScheme(.dark)
}
