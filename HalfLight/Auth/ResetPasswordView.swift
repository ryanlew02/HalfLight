//
//  ResetPasswordView.swift
//  HalfLight
//
//  The "set a new password" screen, presented after the user taps a password
//  reset link in their email and the app redeems it for a recovery session
//  (see `AuthService.handlePasswordResetLink`). Unlike `ChangePasswordView`,
//  no current password is required — the recovery session authorizes the change.
//

import SwiftUI

struct ResetPasswordView: View {
    @Environment(AuthService.self) private var auth

    private enum Field: Hashable { case newPassword, confirm }
    @FocusState private var focusedField: Field?

    @State private var newPassword = ""
    @State private var confirm = ""

    // Same rules as sign-up, so a reset can't land on a weaker password than the
    // one the account was created with.
    private var lengthMet: Bool { (8...20).contains(newPassword.count) }
    private var uppercaseMet: Bool { newPassword.contains(where: \.isUppercase) }
    private var lowercaseMet: Bool { newPassword.contains(where: \.isLowercase) }
    private var numberMet: Bool { newPassword.contains(where: \.isNumber) }
    private var passwordsMatch: Bool { !confirm.isEmpty && newPassword == confirm }

    private var allRequirementsMet: Bool {
        lengthMet && uppercaseMet && lowercaseMet && numberMet && passwordsMatch
    }

    private var canSubmit: Bool { allRequirementsMet && !auth.isWorking }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("New password", text: $newPassword)
                        .textContentType(.newPassword)
                        .focused($focusedField, equals: .newPassword)
                    SecureField("Confirm new password", text: $confirm)
                        .textContentType(.newPassword)
                        .focused($focusedField, equals: .confirm)
                } header: {
                    Text("Choose a new password for your HalfLight account.")
                        .textCase(nil)
                }
                .listRowBackground(Color.dreamSurface)

                Section {
                    requirementRow("8–20 characters", met: lengthMet)
                    requirementRow("An uppercase letter", met: uppercaseMet)
                    requirementRow("A lowercase letter", met: lowercaseMet)
                    requirementRow("A number", met: numberMet)
                    requirementRow("Passwords match", met: passwordsMatch)
                }
                .listRowBackground(Color.dreamSurface)

                if let error = auth.errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red)
                    }
                    .listRowBackground(Color.dreamSurface)
                }

                Section {
                    Button {
                        Task {
                            let ok = await auth.completePasswordReset(newPassword: newPassword)
                            if ok { newPassword = ""; confirm = "" }
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if auth.isWorking {
                                ProgressView()
                            } else {
                                Text("Set new password").fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(!canSubmit)
                }
                .listRowBackground(Color.dreamSurface)
            }
            .scrollContentBackground(.hidden)
            .background { DreamBackground() }
            .tint(.dreamPrimary)
            .navigationTitle("Reset Password")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { auth.isPresentingPasswordReset = false }
                }
                // A Done button above the keyboard to dismiss it from either of
                // the secure fields, which have no Return key to do so.
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.dreamPrimary)
                }
            }
            .onAppear { auth.errorMessage = nil }
        }
    }

    /// A single live-ticking requirement row, mirroring the sign-up checklist.
    private func requirementRow(_ text: String, met: Bool) -> some View {
        HStack(spacing: DreamMetric.xs) {
            Image(systemName: met ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 13))
                .foregroundStyle(met ? .green : Color.dreamText.opacity(0.3))
            Text(text)
                .font(.dreamBody(13, .medium))
                .foregroundStyle(met ? Color.dreamText.opacity(0.8) : .secondary)
        }
        .animation(.easeOut(duration: 0.15), value: met)
    }
}
