//
//  EditProfileView.swift
//  HalfLight
//
//  Edit the dreamer's public bio. Reached from the Profile tab, saved via
//  AuthService to the `profiles` row. (Changing the username lives under
//  Settings › Account, where it gets its own rate-limited screen.)
//

import SwiftUI

struct EditProfileView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appTheme") private var theme: AppTheme = .system

    @State private var bio = ""

    /// Bios stay short — they headline the profile, not a back-story.
    private let bioLimit = 200

    var body: some View {
        Form {
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
            KeyboardDoneButton()
        }
        .onAppear {
            bio = auth.bio ?? ""
            auth.errorMessage = nil
        }
        .tint(.dreamPrimary)
        .preferredColorScheme(theme.colorScheme)
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

    private func save() {
        Task {
            let ok = await auth.updateBio(bio)
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
