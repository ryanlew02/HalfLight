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
            }

            if mode == .signIn {
                Button("Forgot password?") {
                    Task { await auth.sendPasswordReset(email: email) }
                }
                .font(.dreamBody(13, .semibold))
                .foregroundStyle(Color.dreamPrimary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .disabled(auth.isWorking)
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
            case .signUp: await auth.signUp(email: email, password: password)
            case .signIn: await auth.signIn(email: email, password: password)
            }
        }
    }
}
