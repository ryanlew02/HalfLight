//
//  AuthView.swift
//  HalfLight
//
//  Account sheet: create an account or sign in (email/password or Sign in with
//  Apple), and manage the current session when already signed in.
//

import SwiftUI
import AuthenticationServices

struct AuthView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    private enum Mode {
        case signUp, signIn

        var title: String { self == .signUp ? "Create your account" : "Welcome back" }
        var cta: String { self == .signUp ? "Create account" : "Sign in" }
        var prompt: String { self == .signUp ? "Already have an account?" : "New to HalfLight?" }
        var toggle: String { self == .signUp ? "Sign in" : "Create one" }
    }

    @State private var mode: Mode = .signUp
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showForgotPassword = false

    var body: some View {
        NavigationStack {
            ScrollView {
                Group {
                    if auth.isSignedIn {
                        signedIn
                    } else {
                        signedOut
                    }
                }
                .padding(DreamMetric.screen)
            }
            .background { NightSkyBackground() }
            .navigationDestination(isPresented: $showForgotPassword) {
                ForgotPasswordView(email: email)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.dreamText.opacity(0.6))
                    }
                    .accessibilityLabel("Close")
                }
            }
            .onChange(of: auth.isSignedIn) { _, signedIn in
                if signedIn { dismiss() }
            }
        }
    }

    // MARK: - Signed out (sign up / sign in)

    private var signedOut: some View {
        VStack(alignment: .leading, spacing: DreamMetric.xl) {
            header

            VStack(spacing: DreamMetric.md) {
                field("Email", text: $email, isSecure: false)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                field("Password", text: $password, isSecure: true)
                    .textContentType(mode == .signUp ? .newPassword : .password)
                if mode == .signUp {
                    field("Confirm password", text: $confirmPassword, isSecure: true)
                        .textContentType(.newPassword)
                }
            }

            if let error = auth.errorMessage {
                errorBanner(error)
            }

            if let info = auth.infoMessage {
                infoBanner(info)
            }

            Button(action: submit) {
                if auth.isWorking {
                    ProgressView().tint(.white)
                } else {
                    Text(mode.cta)
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(auth.isWorking)

            divider

            SignInWithAppleButton(.continue) { request in
                auth.prepareAppleRequest(request)
            } onCompletion: { result in
                Task { await auth.completeAppleSignIn(result) }
            }
            .signInWithAppleButtonStyle(scheme == .dark ? .white : .black)
            .frame(height: 50)
            .clipShape(.rect(cornerRadius: DreamMetric.controlRadius))

            toggleMode

            Button("Forgot password?") {
                auth.errorMessage = nil
                auth.infoMessage = nil
                showForgotPassword = true
            }
            .font(.dreamBody(13, .semibold))
            .foregroundStyle(Color.dreamPrimary)
            .frame(maxWidth: .infinity)
            .disabled(auth.isWorking)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DreamMetric.sm) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color.dreamPrimary)
            Text(mode.title)
                .font(.dreamDisplay(28))
            Text("Back up your dreams to the cloud and keep them synced across your devices.")
                .font(.dreamBody(15))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var toggleMode: some View {
        HStack(spacing: DreamMetric.xs) {
            Text(mode.prompt)
                .foregroundStyle(.secondary)
            Button(mode.toggle) {
                withAnimation { mode = (mode == .signUp ? .signIn : .signUp) }
                confirmPassword = ""
                auth.errorMessage = nil
                auth.infoMessage = nil
            }
            .foregroundStyle(Color.dreamPrimary)
            .fontWeight(.bold)
        }
        .font(.dreamBody(14))
        .frame(maxWidth: .infinity)
    }

    // MARK: - Signed in

    private var signedIn: some View {
        VStack(spacing: DreamMetric.lg) {
            Image(systemName: "checkmark.icloud.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.dreamPrimary)
            Text("You're signed in")
                .font(.dreamDisplay(24))
            Text(auth.email ?? "Your dreams are backed up.")
                .font(.dreamBody(15))
                .foregroundStyle(.secondary)

            if let error = auth.errorMessage {
                errorBanner(error)
            }

            Button {
                Task { await auth.signOut() }
            } label: {
                if auth.isWorking {
                    ProgressView()
                } else {
                    Text("Sign out")
                }
            }
            .buttonStyle(GhostButtonStyle())
            .disabled(auth.isWorking)
            .padding(.top, DreamMetric.sm)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, DreamMetric.xxl)
    }

    // MARK: - Pieces

    private func field(_ placeholder: String, text: Binding<String>, isSecure: Bool) -> some View {
        Group {
            if isSecure {
                SecureField(placeholder, text: text)
            } else {
                TextField(placeholder, text: text)
            }
        }
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

    private func infoBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: DreamMetric.sm) {
            Image(systemName: "checkmark.circle.fill")
            Text(message)
                .font(.dreamBody(13, .medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Color.dreamPrimary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DreamMetric.md)
        .background(Color.dreamPrimary.opacity(0.12), in: .rect(cornerRadius: DreamMetric.controlRadius))
    }

    private var divider: some View {
        HStack(spacing: DreamMetric.md) {
            line
            Text("or")
                .font(.dreamBody(13))
                .foregroundStyle(.secondary)
            line
        }
    }

    private var line: some View {
        Rectangle()
            .fill(Color.dreamText.opacity(0.12))
            .frame(height: 1)
    }

    private func submit() {
        Task {
            switch mode {
            case .signUp:
                guard password == confirmPassword else {
                    auth.errorMessage = "Passwords don't match."
                    return
                }
                await auth.signUp(email: email, password: password)
            case .signIn:
                await auth.signIn(email: email, password: password)
            }
        }
    }
}

// MARK: - Forgot password

/// A dedicated screen for requesting a password-reset email. Pushed from the
/// sign-in / sign-up form; carries over whatever email was already typed.
struct ForgotPasswordView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State var email: String

    private var canSubmit: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        return trimmed.contains("@") && trimmed.contains(".") && !auth.isWorking
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DreamMetric.xl) {
                header

                emailField
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                if let error = auth.errorMessage {
                    banner(error, symbol: "exclamationmark.triangle.fill", tint: .red)
                }
                if let info = auth.infoMessage {
                    banner(info, symbol: "checkmark.circle.fill", tint: .dreamPrimary)
                }

                Button(action: send) {
                    if auth.isWorking {
                        ProgressView().tint(.white)
                    } else {
                        Text("Send reset link")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canSubmit)
                .opacity(canSubmit ? 1 : 0.5)
            }
            .padding(DreamMetric.screen)
        }
        .background { NightSkyBackground() }
        .navigationTitle("Reset password")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            auth.errorMessage = nil
            auth.infoMessage = nil
        }
        .onDisappear {
            // Don't let this screen's confirmation linger on the auth form.
            auth.infoMessage = nil
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DreamMetric.sm) {
            Image(systemName: "key.fill")
                .font(.system(size: 36))
                .foregroundStyle(Color.dreamPrimary)
            Text("Forgot your password?")
                .font(.dreamDisplay(26))
            Text("Enter your account email and we'll send you a link to reset your password.")
                .font(.dreamBody(15))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emailField: some View {
        TextField("Email", text: $email)
            .font(.dreamBody(16))
            .padding(.vertical, 14)
            .padding(.horizontal, DreamMetric.lg)
            .background(Color.dreamSurface, in: .rect(cornerRadius: DreamMetric.controlRadius))
            .overlay(
                RoundedRectangle(cornerRadius: DreamMetric.controlRadius)
                    .stroke(Color.dreamText.opacity(0.12), lineWidth: 1)
            )
    }

    private func banner(_ message: String, symbol: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: DreamMetric.sm) {
            Image(systemName: symbol)
            Text(message)
                .font(.dreamBody(13, .medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DreamMetric.md)
        .background(tint.opacity(0.12), in: .rect(cornerRadius: DreamMetric.controlRadius))
    }

    private func send() {
        Task {
            await auth.sendPasswordReset(email: email.trimmingCharacters(in: .whitespaces))
        }
    }
}
