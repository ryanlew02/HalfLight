//
//  EditProfileView.swift
//  HalfLight
//
//  Edit the dreamer's public profile: username and bio. Changing the username is
//  rate-limited to once every 30 days (enforced server-side); the field locks and
//  shows when it can next change. Reached from the Profile tab, saved via
//  AuthService to the `profiles` row.
//

import SwiftUI

struct EditProfileView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appTheme") private var theme: AppTheme = .system

    @State private var username = ""
    @State private var bio = ""
    @State private var showUsernameWarning = false

    /// Bios stay short — they headline the profile, not a back-story.
    private let bioLimit = 200

    /// The username can't be changed while inside its 30-day cooldown.
    private var inCooldown: Bool { auth.usernameCooldownEnds != nil }

    /// The normalized handle the way `AuthService` will store it.
    private var normalizedUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var usernameChanged: Bool {
        normalizedUsername != (auth.username ?? "")
    }

    var body: some View {
        Form {
            usernameSection
            bioSection
            errorSection
        }
        .scrollContentBackground(.hidden)
        .background { DreamBackground() }
        .navigationTitle("Edit Profile")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(action: save) {
                    if auth.isWorking {
                        ProgressView()
                    } else {
                        Text("Save")
                    }
                }
                .fontWeight(.semibold)
                .disabled(auth.isWorking)
            }
        }
        .alert("Change username?", isPresented: $showUsernameWarning) {
            Button("Change", role: .destructive) { commit() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You won't be able to change your username again for 30 days.")
        }
        .onAppear {
            username = auth.username ?? ""
            bio = auth.bio ?? ""
            auth.errorMessage = nil
        }
        .tint(.dreamPrimary)
        .preferredColorScheme(theme.colorScheme)
    }

    private var usernameSection: some View {
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
            }

            Text(usernameHint)
                .font(.dreamCaption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .listRowBackground(Color.dreamSurface)
    }

    private var bioSection: some View {
        Section("Bio") {
            TextField(
                "Tell other dreamers about yourself…",
                text: $bio,
                axis: .vertical
            )
            .lineLimit(3...6)
            .onChange(of: bio) { _, newValue in
                if newValue.count > bioLimit {
                    bio = String(newValue.prefix(bioLimit))
                }
            }

            Text("\(bio.count)/\(bioLimit)")
                .font(.dreamCaption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .listRowBackground(Color.dreamSurface)
    }

    @ViewBuilder
    private var errorSection: some View {
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

    /// Guidance under the username field: the cooldown date if locked, otherwise
    /// the heads-up that a change starts a new 30-day lock.
    private var usernameHint: String {
        if let ends = auth.usernameCooldownEnds {
            return "You changed your username recently. You can change it again on \(ends.formatted(date: .abbreviated, time: .omitted))."
        }
        return "Choose carefully — once you change your username, you can't change it again for 30 days."
    }

    /// Warn before committing a username change; bio-only edits save straight away.
    private func save() {
        if usernameChanged {
            showUsernameWarning = true
        } else {
            commit()
        }
    }

    private func commit() {
        Task {
            var ok = true
            if usernameChanged {
                ok = await auth.updateUsername(username)
            }
            if ok {
                ok = await auth.updateBio(bio)
            }
            SoundManager.shared.play(ok ? .reward : .wrong)
            if ok { dismiss() }
        }
    }
}

#Preview("Light") {
    NavigationStack {
        EditProfileView()
            .environment(AuthService())
    }
}

#Preview("Dark") {
    NavigationStack {
        EditProfileView()
            .environment(AuthService())
            .preferredColorScheme(.dark)
    }
}
