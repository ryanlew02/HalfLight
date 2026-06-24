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
    /// Start voice dictation automatically on appear — used by the morning
    /// quick-capture from a widget / Control so the mic is live the instant the
    /// sheet opens. Only honored when creating a new dream.
    var autoDictate: Bool = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(SubscriptionManager.self) private var subscriptions
    @State private var showDeleteConfirm = false
    /// Presented when a non-subscriber taps an AI feature.
    @State private var showPaywall = false

    @State private var title: String
    @State private var entry: String
    @State private var mood: Dream.Mood
    @State private var tagText: String
    /// Visibility — private by default; public lets the dream be shared to the feed.
    @State private var isPublic: Bool
    /// Whether the dreamer was lucid — non-lucid by default.
    @State private var isLucid: Bool

    // AI analysis captured in-form, so a dream can be interpreted before it's saved.
    @State private var aiCategory: String?
    @State private var aiMeaning: String?
    @State private var aiThemes: [String]

    @AppStorage("appTheme") private var theme: AppTheme = .system
    @State private var transcriber = DreamTranscriber()
    @State private var entryBeforeDictation = ""
    @State private var analyzer = DreamAnalyzer()
    /// Guards the auto-dictation kickoff so it only fires once per presentation.
    @State private var didAutoStartDictation = false

    init(
        existingDream: Dream? = nil,
        autoDictate: Bool = false,
        onSave: @escaping (DreamDraft) -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        self.existingDream = existingDream
        self.autoDictate = autoDictate
        self.onSave = onSave
        self.onDelete = onDelete
        _title = State(initialValue: existingDream?.title ?? "")
        _entry = State(initialValue: existingDream?.entry ?? "")
        _mood = State(initialValue: existingDream?.mood ?? .vivid)
        _tagText = State(initialValue: existingDream?.tags.joined(separator: ", ") ?? "")
        _isPublic = State(initialValue: existingDream?.isPublic ?? false)
        _isLucid = State(initialValue: existingDream?.isLucid ?? false)
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

                    autoTitleControl
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
                            Label(localized(mood.rawValue), systemImage: mood.symbol)
                                .tag(mood)
                        }
                    }
                    #if os(iOS)
                    .pickerStyle(.navigationLink)
                    #endif
                }
                .listRowBackground(Color.dreamSurface)

                Section("Visibility") {
                    Picker("Visibility", selection: $isPublic) {
                        Label("Private", systemImage: "lock.fill").tag(false)
                        Label("Public", systemImage: "globe").tag(true)
                    }
                    #if os(iOS)
                    .pickerStyle(.segmented)
                    #endif
                    .labelsHidden()

                    Text(isPublic
                         ? "This dream is shared to the feed for others to see."
                         : "Only you can see this dream.")
                        .font(.dreamCaption)
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(Color.dreamSurface)

                Section("Lucidity") {
                    Picker("Lucidity", selection: $isLucid) {
                        Text("Non-lucid").tag(false)
                        Text("Lucid").tag(true)
                    }
                    #if os(iOS)
                    .pickerStyle(.segmented)
                    #endif
                    .labelsHidden()

                    Text(isLucid
                         ? "You were aware you were dreaming."
                         : "You weren't aware you were dreaming.")
                        .font(.dreamCaption)
                        .foregroundStyle(.secondary)
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
            .task { await autoStartDictationIfNeeded() }
            // Stop listening the moment the app leaves the foreground — leaving the
            // mic live in the background would be unsettling.
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { transcriber.stop() }
            }
            .onDisappear { transcriber.stop() }
            .sheet(isPresented: $showPaywall) { PaywallView() }
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
            isPublic: isPublic,
            isLucid: isLucid,
            aiCategory: aiMeaning == nil ? nil : aiCategory,
            aiMeaning: aiMeaning,
            aiThemes: aiMeaning == nil ? [] : aiThemes
        )
        onSave(draft)
        dismiss()
    }

    // MARK: - Auto-title

    /// Title generation draws from the dream description, so it needs entry text.
    private var canAutoTitle: Bool {
        !entry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var autoTitleControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: autoTitle) {
                Label {
                    Text(analyzer.isSuggestingTitle ? "Generating title…" : "Generate title with AI")
                } icon: {
                    if analyzer.isSuggestingTitle {
                        ProgressView()
                    } else {
                        Image(systemName: subscriptions.isSubscribed ? "sparkles" : "lock.fill")
                    }
                }
                .font(.dreamBody(15, .semibold))
                .foregroundStyle(canAutoTitle ? Color.dreamPrimary : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(!canAutoTitle || analyzer.isSuggestingTitle)

            Text("Write your dream below, then let AI name it.")
                .font(.dreamCaption)
                .foregroundStyle(.secondary)
        }
    }

    /// AI features are HalfLight Pro: a non-subscriber tap opens the paywall
    /// instead of spending on the analysis. Returns true when Pro is active.
    private func requirePro() -> Bool {
        guard subscriptions.isSubscribed else {
            SoundManager.shared.play(.tap)
            showPaywall = true
            return false
        }
        return true
    }

    private func autoTitle() {
        guard requirePro() else { return }
        SoundManager.shared.play(.tap)
        Task {
            guard let suggested = await analyzer.suggestTitle(
                entry: entry,
                mood: mood.rawValue
            ) else {
                SoundManager.shared.play(.wrong)
                return
            }
            title = suggested
            SoundManager.shared.play(.shimmer)
        }
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
                        Image(systemName: subscriptions.isSubscribed ? "sparkles" : "lock.fill")
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
        guard requirePro() else { return }
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
                            Image(systemName: subscriptions.isSubscribed ? "sparkles" : "lock.fill")
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
        guard requirePro() else { return }
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

    /// Kick off dictation on open for the quick-capture flow, once, for new dreams.
    private func autoStartDictationIfNeeded() async {
        guard autoDictate, !isEditing, !didAutoStartDictation else { return }
        didAutoStartDictation = true
        entryBeforeDictation = entry
        await transcriber.start()
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
