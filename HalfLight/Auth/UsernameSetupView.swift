//
//  UsernameSetupView.swift
//  HalfLight
//
//  A blocking onboarding gate shown when someone is signed in but hasn't chosen a
//  username yet (e.g. after Sign in with Apple, or an older account from before
//  usernames existed). They can't reach the app until they pick a unique handle
//  and confirm their name — or sign out.
//

import SwiftUI

struct UsernameSetupView: View {
    @Environment(AuthService.self) private var auth

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var username = ""

    private var canSubmit: Bool {
        !auth.isWorking
            && !firstName.trimmingCharacters(in: .whitespaces).isEmpty
            && !lastName.trimmingCharacters(in: .whitespaces).isEmpty
            && AuthService.isValidUsername(username.trimmingCharacters(in: .whitespaces).lowercased())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DreamMetric.xl) {
                header

                VStack(spacing: DreamMetric.md) {
                    HStack(spacing: DreamMetric.md) {
                        field("First name", text: $firstName)
                            .textContentType(.givenName)
                        field("Last name", text: $lastName)
                            .textContentType(.familyName)
                    }
                    field("Username", text: $username)
                        .textContentType(.username)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()

                    Text("Letters, numbers, and underscores. This is how others will find you.")
                        .font(.dreamCaption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let error = auth.errorMessage {
                    errorBanner(error)
                }

                Button(action: submit) {
                    if auth.isWorking {
                        ProgressView().tint(.white)
                    } else {
                        Text("Continue")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canSubmit)
                .opacity(canSubmit ? 1 : 0.5)

                Button("Sign out") {
                    Task { await auth.signOut() }
                }
                .font(.dreamBody(13, .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .disabled(auth.isWorking)
            }
            .padding(DreamMetric.screen)
        }
        .background { NightSkyBackground() }
        .onAppear {
            firstName = auth.firstName ?? ""
            lastName = auth.lastName ?? ""
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DreamMetric.sm) {
            Image(systemName: "at.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color.dreamPrimary)
            Text("Choose your username")
                .font(.dreamDisplay(28))
            Text("One last step — pick a unique handle and tell us your name to finish setting up your account.")
                .font(.dreamBody(15))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, DreamMetric.xl)
    }

    private func field(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .font(.dreamBody(16))
            .padding(.vertical, 14)
            .padding(.horizontal, DreamMetric.lg)
            .background(Color.dreamSurface, in: .rect(cornerRadius: DreamMetric.controlRadius))
            .overlay(
                RoundedRectangle(cornerRadius: DreamMetric.controlRadius)
                    .stroke(Color.dreamText.opacity(0.12), lineWidth: 1)
            )
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: DreamMetric.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message)
                .font(.dreamBody(13, .medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.red)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DreamMetric.md)
        .background(Color.red.opacity(0.1), in: .rect(cornerRadius: DreamMetric.controlRadius))
    }

    private func submit() {
        Task {
            let ok = await auth.completeProfile(
                username: username,
                firstName: firstName,
                lastName: lastName
            )
            SoundManager.shared.play(ok ? .reward : .wrong)
        }
    }
}
