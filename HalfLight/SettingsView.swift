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

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    ProSettingsView()
                } label: {
                    SettingRow(
                        title: "HalfLight Pro",
                        systemImage: "sparkles",
                        value: subscriptions.isSubscribed ? "Active" : "Upgrade"
                    )
                }
            } footer: {
                Text(subscriptions.isSubscribed
                     ? "AI features are unlocked. Thank you for supporting HalfLight."
                     : "Unlock AI dream analysis, auto-tags, and AI titles.")
            }
            .listRowBackground(Color.dreamSurface)

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
                    SettingRow(title: "Notifications", systemImage: "bell", value: dailyReminder ? "On" : "Off")
                }
                NavigationLink {
                    SoundSettingsView()
                } label: {
                    SettingRow(title: "Sound & Haptics", systemImage: "speaker.wave.2", value: soundEnabled ? "On" : "Off")
                }
            }
            .listRowBackground(Color.dreamSurface)

            Section {
                NavigationLink {
                    AccountSettingsView()
                } label: {
                    SettingRow(title: "Account", systemImage: "person.crop.circle", value: auth.isSignedIn ? (auth.email ?? "Signed in") : "Sign in")
                }
                NavigationLink {
                    AboutSettingsView()
                } label: {
                    SettingRow(title: "About", systemImage: "info.circle", value: nil)
                }
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
        .background { DreamBackground() }
        .tint(.dreamPrimary)
        .navigationTitle("Settings")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

/// A settings menu row: icon + title on the left, optional current value on the right.
private struct SettingRow: View {
    let title: String
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

// MARK: - HalfLight Pro

/// Subscription status + management: upgrade (opens the paywall), restore, and a
/// link to the system "Manage Subscription" sheet.
struct ProSettingsView: View {
    @Environment(SubscriptionManager.self) private var subscriptions
    @State private var showPaywall = false

    var body: some View {
        Form {
            Section {
                HStack {
                    Label("Status", systemImage: "sparkles")
                    Spacer()
                    Text(subscriptions.isSubscribed ? "Active" : "Not subscribed")
                        .foregroundStyle(subscriptions.isSubscribed ? Color.dreamPrimary : .secondary)
                }
            } footer: {
                Text(subscriptions.isSubscribed
                     ? "AI dream analysis, auto-tags, and AI titles are unlocked."
                     : "Subscribe to unlock AI dream analysis, auto-tags, and AI titles.")
            }
            .listRowBackground(Color.dreamSurface)

            Section {
                if !subscriptions.isSubscribed {
                    Button {
                        SoundManager.shared.play(.tap)
                        showPaywall = true
                    } label: {
                        Label("Upgrade to Pro", systemImage: "crown")
                    }
                }
                Button {
                    Task { await subscriptions.restore() }
                } label: {
                    Label("Restore Purchases", systemImage: "arrow.clockwise")
                }
                if subscriptions.isSubscribed {
                    Button {
                        Task { await subscriptions.showManageSubscriptions() }
                    } label: {
                        Label("Manage Subscription", systemImage: "gear")
                    }
                }
            }
            .listRowBackground(Color.dreamSurface)
        }
        .scrollContentBackground(.hidden)
        .background { DreamBackground() }
        .tint(.dreamPrimary)
        .navigationTitle("HalfLight Pro")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $showPaywall) { PaywallView() }
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
        .background { DreamBackground() }
        .tint(.dreamPrimary)
        .navigationTitle("Name")
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
        .background { DreamBackground() }
        .tint(.dreamPrimary)
        .navigationTitle("Change Password")
        .onAppear {
            auth.errorMessage = nil
            auth.infoMessage = nil
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
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
}

#Preview("Dark") {
    NavigationStack {
        SettingsView()
    }
    .environment(AuthService())
    .environment(SubscriptionManager())
    .preferredColorScheme(.dark)
}
