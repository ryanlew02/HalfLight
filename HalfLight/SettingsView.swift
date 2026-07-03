//
//  SettingsView.swift
//  HalfLight
//
//  Settings menu. Each row pushes its own dedicated screen.
//

import SwiftUI

struct SettingsView: View {
    @Environment(AuthService.self) private var auth
    @Environment(SubscriptionManager.self) private var subscriptions
    @AppStorage("userName") private var userName = "Dreamer"
    @AppStorage("appTheme") private var theme: AppTheme = .system
    @AppStorage("dailyReminderEnabled") private var dailyReminder = false
    @AppStorage("soundEffectsEnabled") private var soundEnabled = true
    @Environment(LanguageManager.self) private var language
    @State private var showPaywall = false
    @State private var showRestoreResult = false

    var body: some View {
        Form {
            Section {
                Button {
                    SoundManager.shared.play(.tap)
                    if subscriptions.isSubscribed {
                        // Already a member — let them manage / cancel in the App Store.
                        Task { await subscriptions.showManageSubscriptions() }
                    } else {
                        // Straight to the subscribe screen — no interstitial status page.
                        showPaywall = true
                    }
                } label: {
                    ProCallToActionCard(isSubscribed: subscriptions.isSubscribed)
                }
                .buttonStyle(.plain)
                // Gradient as the row background (like the other rows use dreamSurface)
                // so it spans the exact same card width as every other section.
                .listRowBackground(
                    LinearGradient(
                        colors: [.dreamPrimary, .dreamAccent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }

            Section {
                NavigationLink {
                    NameSettingsView()
                } label: {
                    SettingRow(title: "Name", systemImage: "person.text.rectangle", value: userName)
                }
            }
            .listRowBackground(Color.dreamSurface)

            Section {
                NavigationLink {
                    AppearanceSettingsView()
                } label: {
                    SettingRow(title: "Appearance", systemImage: "circle.lefthalf.filled", value: theme.label)
                }
                NavigationLink {
                    NotificationSettingsView()
                } label: {
                    SettingRow(title: "Notifications", systemImage: "bell", value: dailyReminder ? localized("On") : localized("Off"))
                }
                NavigationLink {
                    SoundSettingsView()
                } label: {
                    SettingRow(title: "Sound & Haptics", systemImage: "speaker.wave.2", value: soundEnabled ? localized("On") : localized("Off"))
                }
                NavigationLink {
                    LanguageSettingsView()
                } label: {
                    SettingRow(title: "Language", systemImage: "globe", value: language.current.nativeName)
                }
            }
            .listRowBackground(Color.dreamSurface)

            Section {
                NavigationLink {
                    AccountSettingsView()
                } label: {
                    SettingRow(title: "Account", systemImage: "person.crop.circle", value: auth.isSignedIn ? (auth.email ?? localized("Signed in")) : localized("Sign in"))
                }
                NavigationLink {
                    AboutSettingsView()
                } label: {
                    SettingRow(title: "About", systemImage: "info.circle", value: nil)
                }
                // Re-attach an existing App Store subscription to this account
                // (e.g. on a new device or after reinstalling).
                Button {
                    SoundManager.shared.play(.tap)
                    Task {
                        await subscriptions.restore()
                        showRestoreResult = true
                    }
                } label: {
                    SettingRow(title: "Restore Purchases", systemImage: "arrow.clockwise", value: nil)
                }
                .buttonStyle(.plain)
                .disabled(subscriptions.isPurchasing)
            }
            .listRowBackground(Color.dreamSurface)

            Section {
                if let supportURL = URL(string: "mailto:support@thelanternhours.com") {
                    Link(destination: supportURL) {
                        SettingRow(title: "Support", systemImage: "envelope", value: nil)
                    }
                }
            } footer: {
                Text("Questions or feedback? Reach us at support@thelanternhours.com.")
            }
            .listRowBackground(Color.dreamSurface)
        }
        .scrollContentBackground(.hidden)
        .tabBarClearance()
        .background { DreamBackground() }
        .tint(.dreamPrimary)
        .navigationTitle("Settings")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .alert("Restore Purchases", isPresented: $showRestoreResult) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(restoreResultMessage)
        }
    }

    /// A friendly result message after a Restore attempt.
    private var restoreResultMessage: LocalizedStringKey {
        if subscriptions.isSubscribed && subscriptions.lastSyncSucceeded {
            return "Your HalfLight Pro subscription has been restored."
        } else if !subscriptions.isSubscribed {
            return "We couldn't find an active subscription for your Apple ID. If you believe this is a mistake, email support@thelanternhours.com."
        } else {
            return "Something went wrong restoring your purchase. Please email support@thelanternhours.com and we'll get it sorted."
        }
    }
}

/// The HalfLight Pro entry in Settings — a vivid gradient card that sells the
/// upgrade (tapping opens the subscribe sheet) or, once subscribed, shows the
/// dreamer is a member and taps through to manage / cancel.
private struct ProCallToActionCard: View {
    let isSubscribed: Bool

    var body: some View {
        HStack(spacing: DreamMetric.md) {
            Image(systemName: isSubscribed ? "crown.fill" : "sparkles")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(.white.opacity(0.18), in: .circle)

            VStack(alignment: .leading, spacing: 3) {
                // "HalfLight Pro" is the product name and stays English everywhere;
                // the surrounding copy is translated. The `%@` placeholder lets each
                // language place the brand name correctly.
                (isSubscribed
                    ? Text(verbatim: "HalfLight Pro")
                    : Text(localized("Upgrade to %@", "HalfLight Pro")))
                    .font(.dreamGrotesk(17, .bold))
                    .foregroundStyle(.white)
                Text(localized(isSubscribed
                     ? "You're a member — tap to manage."
                     : "AI dream analysis, auto-tags & titles."))
                    .font(.dreamBody(13, .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: DreamMetric.sm)

            if isSubscribed {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Text(localized("Upgrade"))
                    .font(.dreamGrotesk(13, .bold))
                    .foregroundStyle(Color.dreamPrimary)
                    .padding(.horizontal, DreamMetric.md)
                    .padding(.vertical, 7)
                    .background(.white, in: .capsule)
            }
        }
        .padding(.vertical, DreamMetric.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A settings menu row: icon + title on the left, optional current value on the right.
private struct SettingRow: View {
    let title: LocalizedStringKey
    let systemImage: String
    let value: String?

    var body: some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            if let value {
                Text(value)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Name

struct NameSettingsView: View {
    @Environment(AuthService.self) private var auth
    @AppStorage("userName") private var userName = "Dreamer"
    @State private var draft = ""

    var body: some View {
        Form {
            if auth.isSignedIn {
                // Signed in: the name comes from the account and can't be edited
                // here — it's changed via the account / profile instead.
                Section {
                    HStack {
                        Text("Name")
                        Spacer()
                        Text(auth.firstName?.isEmpty == false ? auth.firstName! : userName)
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Your name comes from your account. Sign out to use a custom name on this device.")
                }
                .listRowBackground(Color.dreamSurface)
            } else {
                Section {
                    HStack {
                        TextField("Your name", text: $draft)
                            .textContentType(.givenName)
                            .submitLabel(.done)
                        if !draft.isEmpty {
                            Button {
                                draft = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Clear name")
                        }
                    }
                } footer: {
                    Text("This is how HalfLight greets you on the Home screen.")
                }
                .listRowBackground(Color.dreamSurface)
            }
        }
        .scrollContentBackground(.hidden)
        .tabBarClearance()
        .background { DreamBackground() }
        .tint(.dreamPrimary)
        .navigationTitle("Name")
        .keyboardDoneToolbar()
        .onAppear { draft = userName }
        .onChange(of: draft) { _, newValue in
            // Only a signed-out dreamer can set a custom local name.
            guard !auth.isSignedIn else { return }
            let trimmed = newValue.trimmingCharacters(in: .whitespaces)
            userName = trimmed.isEmpty ? "Dreamer" : trimmed
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - Appearance

struct AppearanceSettingsView: View {
    @AppStorage("appTheme") private var theme: AppTheme = .system

    var body: some View {
        Form {
            Section {
                ForEach(AppTheme.allCases) { option in
                    Button {
                        theme = option
                    } label: {
                        HStack {
                            Text(option.label)
                                .foregroundStyle(Color.dreamText)
                            Spacer()
                            if theme == option {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.dreamPrimary)
                            }
                        }
                    }
                }
            } footer: {
                Text("System follows your device's appearance setting.")
            }
            .listRowBackground(Color.dreamSurface)
        }
        .scrollContentBackground(.hidden)
        .tabBarClearance()
        .background { DreamBackground() }
        .tint(.dreamPrimary)
        .navigationTitle("Appearance")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - Notifications

struct NotificationSettingsView: View {
    @AppStorage("dailyReminderEnabled") private var dailyReminder = false
    @AppStorage("morningReminderMinutes") private var morningReminderMinutes = 9 * 60

    /// Bridges the minutes-since-midnight store to the time picker's `Date`.
    private var morningTime: Binding<Date> {
        Binding {
            Calendar.current.date(
                bySettingHour: morningReminderMinutes / 60,
                minute: morningReminderMinutes % 60,
                second: 0,
                of: .now
            ) ?? .now
        } set: { newValue in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            morningReminderMinutes = (parts.hour ?? 9) * 60 + (parts.minute ?? 0)
        }
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $dailyReminder) {
                    Label("Dream reminders", systemImage: "bell")
                }
                if dailyReminder {
                    DatePicker(
                        selection: morningTime,
                        displayedComponents: .hourAndMinute
                    ) {
                        Label("Morning reminder", systemImage: "sunrise")
                    }
                }
            } footer: {
                Text("Gentle nudges to keep your dream journal — and your streak — alive: a morning prompt at your chosen time to capture last night's dream, a reminder if a day goes by, and an evening heads-up when your streak is about to break. If the toggle switches back off, notifications are disabled for HalfLight in your device's Settings.")
            }
            .listRowBackground(Color.dreamSurface)
        }
        .scrollContentBackground(.hidden)
        .tabBarClearance()
        .background { DreamBackground() }
        .tint(.dreamPrimary)
        .navigationTitle("Notifications")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - Sound & Haptics

struct SoundSettingsView: View {
    @AppStorage("soundEffectsEnabled") private var soundEnabled = true
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $soundEnabled) {
                    Label("Sound effects", systemImage: "speaker.wave.2.fill")
                }
                Toggle(isOn: $hapticsEnabled) {
                    Label("Haptics", systemImage: "hand.tap.fill")
                }
            } footer: {
                Text("Little sounds and taps when you earn XP, answer questions, and move around. They mix with your music and follow the silent switch.")
            }
            .listRowBackground(Color.dreamSurface)
        }
        .scrollContentBackground(.hidden)
        .tabBarClearance()
        .background { DreamBackground() }
        .tint(.dreamPrimary)
        .navigationTitle("Sound & Haptics")
        // Give an instant taste of the change when turning effects on.
        .onChange(of: soundEnabled) { _, isOn in
            if isOn { SoundManager.shared.play(.reward) }
        }
        .onChange(of: hapticsEnabled) { _, isOn in
            if isOn { SoundManager.shared.play(.tap) }
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - Language

struct LanguageSettingsView: View {
    @Environment(LanguageManager.self) private var language

    var body: some View {
        Form {
            Section {
                ForEach(AppLanguage.allCases) { option in
                    Button {
                        SoundManager.shared.play(.tap)
                        language.current = option
                    } label: {
                        HStack {
                            Text(option.nativeName)
                                .foregroundStyle(Color.dreamText)
                            Spacer()
                            if language.current == option {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.dreamPrimary)
                            }
                        }
                    }
                }
            } footer: {
                Text("Changes apply instantly across the app. Your dreams stay in the language you wrote them.")
            }
            .listRowBackground(Color.dreamSurface)
        }
        .scrollContentBackground(.hidden)
        .tabBarClearance()
        .background { DreamBackground() }
        .tint(.dreamPrimary)
        .navigationTitle("Language")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - Account

struct AccountSettingsView: View {
    @Environment(AuthService.self) private var auth
    @State private var showAuth = false
    @State private var showDeleteConfirm = false

    var body: some View {
        Form {
            if let error = auth.errorMessage {
                Section {
                    Text(error)
                        .font(.dreamBody(13, .medium))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .listRowBackground(Color.dreamSurface)
            }

            if auth.isSignedIn {
                Section {
                    LabeledContent("Email", value: auth.email ?? "—")
                } header: {
                    Text("Signed in")
                } footer: {
                    Text("Your dreams are backed up and synced to this account.")
                }
                .listRowBackground(Color.dreamSurface)

                Section {
                    NavigationLink {
                        UsernameSettingsView()
                    } label: {
                        SettingRow(
                            title: "Username",
                            systemImage: "at",
                            value: auth.username.map { "@\($0)" }
                        )
                    }
                }
                .listRowBackground(Color.dreamSurface)

                if auth.canChangePassword {
                    Section {
                        NavigationLink {
                            ChangePasswordView()
                        } label: {
                            SettingRow(title: "Change password", systemImage: "key", value: nil)
                        }
                    }
                    .listRowBackground(Color.dreamSurface)
                }

                Section {
                    Button(role: .destructive) {
                        Task { await auth.signOut() }
                    } label: {
                        HStack {
                            Spacer()
                            if auth.isWorking {
                                ProgressView()
                            } else {
                                Text("Sign out")
                            }
                            Spacer()
                        }
                    }
                    .disabled(auth.isWorking)
                }
                .listRowBackground(Color.dreamSurface)

                Section {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("Delete account")
                                .foregroundStyle(.red)
                            Spacer()
                        }
                    }
                    .disabled(auth.isWorking)
                } footer: {
                    Text("Permanently deletes your account and every dream backed up to it. This can't be undone.")
                }
                .listRowBackground(Color.dreamSurface)
            } else {
                Section {
                    Button {
                        showAuth = true
                    } label: {
                        Label("Sign in or create account", systemImage: "person.crop.circle.badge.plus")
                    }
                } footer: {
                    Text("Sign in to back up your dreams and sync them across devices.")
                }
                .listRowBackground(Color.dreamSurface)
            }
        }
        .scrollContentBackground(.hidden)
        .tabBarClearance()
        .background { DreamBackground() }
        .tint(.dreamPrimary)
        .navigationTitle("Account")
        .sheet(isPresented: $showAuth) {
            AuthView()
        }
        .confirmationDialog(
            "Delete your account?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete account", role: .destructive) {
                Task {
                    let ok = await auth.deleteAccount()
                    SoundManager.shared.play(ok ? .tap : .wrong)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your account and all dreams backed up to it. This can't be undone.")
        }
        .onAppear { auth.errorMessage = nil }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - Change password

struct ChangePasswordView: View {
    @Environment(AuthService.self) private var auth

    @State private var current = ""
    @State private var newPassword = ""
    @State private var confirm = ""

    private var passwordsMatch: Bool { newPassword == confirm }

    private var canSubmit: Bool {
        !current.isEmpty && newPassword.count >= 6 && passwordsMatch && !auth.isWorking
    }

    var body: some View {
        Form {
            Section {
                SecureField("Current password", text: $current)
                    .textContentType(.password)
            }
            .listRowBackground(Color.dreamSurface)

            Section {
                SecureField("New password", text: $newPassword)
                    .textContentType(.newPassword)
                SecureField("Confirm new password", text: $confirm)
                    .textContentType(.newPassword)
            } footer: {
                if !confirm.isEmpty && !passwordsMatch {
                    Text("Passwords don't match.")
                        .foregroundStyle(.red)
                } else {
                    Text("Use at least 6 characters.")
                }
            }
            .listRowBackground(Color.dreamSurface)

            if let error = auth.errorMessage {
                Section {
                    Text(error).foregroundStyle(.red)
                }
                .listRowBackground(Color.dreamSurface)
            }

            if let info = auth.infoMessage {
                Section {
                    Label(info, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Color.dreamPrimary)
                }
                .listRowBackground(Color.dreamSurface)
            }

            Section {
                Button {
                    Task {
                        let ok = await auth.changePassword(current: current, new: newPassword)
                        if ok {
                            current = ""; newPassword = ""; confirm = ""
                        }
                    }
                } label: {
                    HStack {
                        Spacer()
                        if auth.isWorking {
                            ProgressView()
                        } else {
                            Text("Update password").fontWeight(.semibold)
                        }
                        Spacer()
                    }
                }
                .disabled(!canSubmit)
            } footer: {
                Button("Forgot password?") {
                    Task { await auth.sendPasswordReset(email: auth.email ?? "") }
                }
                .font(.dreamBody(13, .semibold))
                .foregroundStyle(Color.dreamPrimary)
                .disabled(auth.isWorking)
            }
            .listRowBackground(Color.dreamSurface)
        }
        .scrollContentBackground(.hidden)
        .tabBarClearance()
        .background { DreamBackground() }
        .tint(.dreamPrimary)
        .navigationTitle("Change Password")
        .keyboardDoneToolbar()
        .onAppear {
            auth.errorMessage = nil
            auth.infoMessage = nil
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - Username

/// Change the account username, rate-limited to once every 30 days (enforced
/// server-side). Validates availability live as the dreamer types, so they only
/// ever submit a free handle.
struct UsernameSettingsView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var username = ""
    @State private var showWarning = false

    /// The username can't be changed while inside its 30-day cooldown.
    private var inCooldown: Bool { auth.usernameCooldownEnds != nil }

    /// The normalized handle the way `AuthService` will store it.
    private var normalized: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Whether the typed handle differs from the current one.
    private var changed: Bool { normalized != (auth.username ?? "") }

    /// Save is allowed only for a real change to a confirmed-available handle.
    private var canSave: Bool {
        changed && !inCooldown && !auth.isWorking && auth.usernameStatus == .available
    }

    var body: some View {
        Form {
            Section("Username") {
                HStack(spacing: 2) {
                    Text("@")
                        .font(.dreamBody(16, .semibold))
                        .foregroundStyle(.secondary)
                    TextField("username", text: $username)
                        .font(.dreamBody(16, .semibold))
                        .textContentType(.username)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                        .disabled(inCooldown)
                        .foregroundStyle(inCooldown ? Color.secondary : Color.dreamText)
                        .onChange(of: username) { _, newValue in
                            // Typing your own current handle isn't a change, so don't
                            // flag it as "taken" — just clear the indicator.
                            if changed {
                                auth.checkUsernameAvailability(newValue)
                            } else {
                                auth.resetUsernameStatus()
                            }
                        }
                }

                if changed && !inCooldown {
                    UsernameAvailabilityLabel(status: auth.usernameStatus)
                }

                Text(usernameHint)
                    .font(.dreamCaption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .listRowBackground(Color.dreamSurface)

            if let error = auth.errorMessage {
                Section {
                    Text(error)
                        .font(.dreamBody(13, .medium))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .listRowBackground(Color.dreamSurface)
            }
        }
        .scrollContentBackground(.hidden)
        .tabBarClearance()
        .background { DreamBackground() }
        .tint(.dreamPrimary)
        .navigationTitle("Username")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(action: { showWarning = true }) {
                    if auth.isWorking {
                        ProgressView()
                    } else {
                        Text("Save")
                    }
                }
                .fontWeight(.semibold)
                .disabled(!canSave)
            }
            KeyboardDoneButton()
        }
        .alert("Change username?", isPresented: $showWarning) {
            Button("Change", role: .destructive) { commit() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You won't be able to change your username again for 30 days.")
        }
        .onAppear {
            username = auth.username ?? ""
            auth.errorMessage = nil
            auth.resetUsernameStatus()
        }
        .onDisappear { auth.resetUsernameStatus() }
    }

    /// Guidance under the field: the cooldown date if locked, otherwise the heads-up
    /// that a change starts a new 30-day lock.
    private var usernameHint: String {
        if let ends = auth.usernameCooldownEnds {
            return "You changed your username recently. You can change it again on \(ends.formatted(date: .abbreviated, time: .omitted))."
        }
        return "Choose carefully — once you change your username, you can't change it again for 30 days."
    }

    private func commit() {
        Task {
            let ok = await auth.updateUsername(username)
            SoundManager.shared.play(ok ? .reward : .wrong)
            if ok { dismiss() }
        }
    }
}

// MARK: - About

struct AboutSettingsView: View {
    var body: some View {
        Form {
            Section {
                LabeledContent("Version", value: appVersion)
            }
            .listRowBackground(Color.dreamSurface)
        }
        .scrollContentBackground(.hidden)
        .tabBarClearance()
        .background { DreamBackground() }
        .tint(.dreamPrimary)
        .navigationTitle("About")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }
}

#Preview("Light") {
    NavigationStack {
        SettingsView()
    }
    .environment(AuthService())
    .environment(SubscriptionManager())
    .environment(LanguageManager.shared)
}

#Preview("Dark") {
    NavigationStack {
        SettingsView()
    }
    .environment(AuthService())
    .environment(SubscriptionManager())
    .environment(LanguageManager.shared)
    .preferredColorScheme(.dark)
}
