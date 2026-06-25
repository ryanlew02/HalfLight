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

    @State private var newPassword = ""
    @State private var confirm = ""

    private var passwordsMatch: Bool { newPassword == confirm }

    private var canSubmit: Bool {
        newPassword.count >= 6 && passwordsMatch && !auth.isWorking
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("New password", text: $newPassword)
                        .textContentType(.newPassword)
                    SecureField("Confirm new password", text: $confirm)
                        .textContentType(.newPassword)
                } header: {
                    Text("Choose a new password for your HalfLight account.")
                        .textCase(nil)
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
            }
            .onAppear { auth.errorMessage = nil }
        }
    }
}
