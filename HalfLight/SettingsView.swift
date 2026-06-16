//
//  SettingsView.swift
//  HalfLight
//
//  Settings menu. Each row pushes its own dedicated screen.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("appTheme") private var theme: AppTheme = .system
    @AppStorage("dailyReminderEnabled") private var dailyReminder = false

    var body: some View {
        Form {
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
                    SettingRow(title: "Account", systemImage: "person.crop.circle", value: "Sign in")
                }
                NavigationLink {
                    AboutSettingsView()
                } label: {
                    SettingRow(title: "About", systemImage: "info.circle", value: nil)
                }
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
    var body: some View {
        Form {
            Section {
                Label("Sign in to sync", systemImage: "person.crop.circle")
            } footer: {
                Text("Accounts and cloud sync are coming soon. Your dreams are stored on this device for now.")
            }
            .listRowBackground(Color.dreamSurface)
        }
        .scrollContentBackground(.hidden)
        .background { DreamBackground() }
        .tint(.dreamPrimary)
        .navigationTitle("Account")
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
}

#Preview("Dark") {
    NavigationStack {
        SettingsView()
    }
    .preferredColorScheme(.dark)
}
