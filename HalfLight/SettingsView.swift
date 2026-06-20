//
//  SettingsView.swift
//  HalfLight
//
//  Settings menu. Each row pushes its own dedicated screen.
//

import SwiftUI

struct SettingsView: View {
    @Environment(AuthService.self) private var auth
    @AppStorage("userName") private var userName = "Dreamer"
    @AppStorage("appTheme") private var theme: AppTheme = .system
    @AppStorage("dailyReminderEnabled") private var dailyReminder = false

    var body: some View {
        Form {
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

// MARK: - Name

struct NameSettingsView: View {
    @AppStorage("userName") private var userName = "Dreamer"
    @State private var draft = ""

    var body: some View {
        Form {
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
        .scrollContentBackground(.hidden)
        .background { DreamBackground() }
        .tint(.dreamPrimary)
        .navigationTitle("Name")
        .onAppear { draft = userName }
        .onChange(of: draft) { _, newValue in
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

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $dailyReminder) {
                    Label("Daily dream reminder", systemImage: "bell")
                }
            } footer: {
                Text("A gentle nudge each morning to record your dreams. (Coming soon.)")
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

// MARK: - Account

struct AccountSettingsView: View {
    @Environment(AuthService.self) private var auth
    @State private var showAuth = false

    var body: some View {
        Form {
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
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - Change password

struct ChangePasswordView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

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
}

#Preview("Dark") {
    NavigationStack {
        SettingsView()
    }
    .environment(AuthService())
    .preferredColorScheme(.dark)
}
