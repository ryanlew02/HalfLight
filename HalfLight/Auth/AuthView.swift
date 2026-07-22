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

    /// Open the sheet on "create account" rather than the default "sign in" — used
    /// by onboarding's "Sign up" call to action.
    var startInSignUp = false

    /// Explicit focus targets. Driving focus through `@FocusState` makes the text
    /// fields focus on the first tap (SwiftUI otherwise sometimes needs several)
    /// and lets Return advance through the form.
    private enum Field: Hashable { case firstName, lastName, username, email, password, confirmPassword }
    @FocusState private var focusedField: Field?

    private enum Mode {
        case signUp, signIn

        var title: String { self == .signUp ? "Create your account" : "Welcome back" }
        var cta: String { self == .signUp ? "Create account" : "Sign in" }
        var prompt: String { self == .signUp ? "Already have an account?" : "New to HalfLight?" }
        var toggle: String { self == .signUp ? "Sign in" : "Create one" }
    }

    @State private var mode: Mode = .signIn
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showForgotPassword = false

    /// Gates building the form until the sheet has finished sliding in. The Sign
    /// in with Apple control bridges to UIKit, and creating it mid-presentation
    /// blocks the main thread — the sheet stutters and taps on the fields don't
    /// register until it settles. We show a light placeholder first, then build
    /// the real form a beat later, once the animation is done.
    @State private var isReady = false

    var body: some View {
        NavigationStack {
            ScrollView {
                Group {
                    if !isReady {
                        loadingPlaceholder
                    } else if auth.isSignedIn {
                        signedIn
                    } else if auth.pendingConfirmationEmail != nil {
                        confirmEmail
                    } else {
                        signedOut
                    }
                }
                .padding(DreamMetric.screen)
            }
            .background { NightSkyBackground() }
            .task {
                // Honor the requested starting mode (onboarding opens on sign-up)
                // before the form builds, so there's no flash of the sign-in header.
                if startInSignUp { mode = .signUp }
                // Roughly the sheet's slide-in duration; building the UIKit-backed
                // form before this finishes is what causes the freeze.
                try? await Task.sleep(for: .milliseconds(350))
                withAnimation(.easeOut(duration: 0.2)) { isReady = true }
            }
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
                // A Done button above the keyboard so the user can dismiss it from
                // any field (some fields have no Return key to do this otherwise).
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.dreamPrimary)
                }
            }
            .onChange(of: auth.isSignedIn) { _, signedIn in
                if signedIn { dismiss() }
            }
            // A tapped password-reset link redeems a recovery session and asks to
            // present the "set a new password" screen from RootView. That cover
            // can't appear while this sheet is up, so close ourselves and let it
            // through.
            .onChange(of: auth.isPresentingPasswordReset) { _, presenting in
                if presenting { dismiss() }
            }
        }
    }

    // MARK: - Signed out (sign up / sign in)

    private var signedOut: some View {
        VStack(alignment: .leading, spacing: DreamMetric.xl) {
            header

            VStack(spacing: DreamMetric.md) {
                if mode == .signUp {
                    HStack(spacing: DreamMetric.md) {
                        field("First name", text: $firstName, isSecure: false, contentType: .givenName)
                            .focused($focusedField, equals: .firstName)
                        field("Last name", text: $lastName, isSecure: false, contentType: .familyName)
                            .focused($focusedField, equals: .lastName)
                    }
                    VStack(alignment: .leading, spacing: DreamMetric.xs) {
                        field("Username", text: $username, isSecure: false, contentType: .username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .username)
                            .onChange(of: username) { _, newValue in
                                auth.checkUsernameAvailability(newValue)
                            }
                        UsernameAvailabilityLabel(status: auth.usernameStatus)
                            .padding(.horizontal, DreamMetric.xs)
                    }
                }
                VStack(alignment: .leading, spacing: DreamMetric.xs) {
                    field("Email", text: $email, isSecure: false, contentType: .emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .email)
                    // Live validity on sign-up; stays hidden until they start typing.
                    if mode == .signUp && !email.isEmpty {
                        requirementRow("A valid email address", met: emailValid)
                            .padding(.horizontal, DreamMetric.xs)
                    }
                }
                field("Password", text: $password, isSecure: true, contentType: mode == .signUp ? .newPassword : .password)
                    .focused($focusedField, equals: .password)
                if mode == .signUp {
                    field("Confirm password", text: $confirmPassword, isSecure: true, contentType: .newPassword)
                        .focused($focusedField, equals: .confirmPassword)
                    passwordRequirements
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
            .disabled(auth.isWorking || (mode == .signUp && (auth.usernameStatus == .taken || !emailValid || !allPasswordRequirementsMet)))

            divider

            // Extracted into its own view: this bridges to a UIKit control, so
            // keeping it out of the per-keystroke `body` recompute (its inputs never
            // change) avoids rebuilding the bridge on every character typed.
            AppleSignInButton()

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

            // The agreement that makes the terms binding (and that App Review
            // looks for on apps with user-generated content).
            Text("By continuing, you agree to our [Terms of Use](https://halflightdream.com/terms.html) and [Privacy Policy](https://halflightdream.com/privacy.html).")
                .font(.dreamBody(12))
                .foregroundStyle(.secondary)
                .tint(Color.dreamPrimary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        // Clear any leftover availability state from a prior presentation.
        .onAppear { auth.resetUsernameStatus() }
    }

    // MARK: - Confirm email (after sign-up)

    /// Shown after a sign-up (or a sign-in with a still-unconfirmed account):
    /// the account exists but can't be used until the emailed link is tapped.
    /// Tapping the link on this device deep-links back in and signs them in.
    private var confirmEmail: some View {
        VStack(spacing: DreamMetric.lg) {
            Image(systemName: "envelope.badge.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.dreamPrimary)
            Text("Confirm your email")
                .font(.dreamDisplay(24))
            Text("We sent a confirmation link to \(auth.pendingConfirmationEmail ?? ""). Open the email on this device and tap the link to finish creating your account.")
                .font(.dreamBody(15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let error = auth.errorMessage {
                errorBanner(error)
            }
            if let info = auth.infoMessage {
                infoBanner(info)
            }

            Button {
                Task { await auth.resendConfirmation() }
            } label: {
                if auth.isWorking {
                    ProgressView().tint(.white)
                } else {
                    Text("Resend email")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(auth.isWorking)

            Button("Back to sign in") {
                auth.cancelPendingConfirmation()
                withAnimation { mode = .signIn }
            }
            .font(.dreamBody(14, .semibold))
            .foregroundStyle(Color.dreamPrimary)
            .disabled(auth.isWorking)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, DreamMetric.xxl)
    }

    // MARK: - Loading placeholder

    /// Shown for the brief moment while the sheet animates in, before the real
    /// form is built. Keeps the presentation smooth and gives the user something
    /// on-brand to look at rather than a blank, unresponsive sheet.
    private var loadingPlaceholder: some View {
        VStack(spacing: DreamMetric.lg) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color.dreamPrimary)
            ProgressView()
                .tint(Color.dreamPrimary)
        }
        .frame(maxWidth: .infinity, minHeight: 420)
        .padding(.top, DreamMetric.xxl)
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
                firstName = ""
                lastName = ""
                username = ""
                auth.resetUsernameStatus()
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

    // MARK: - Email & password requirements

    /// Whether the typed email is well-formed (`local@domain.tld`).
    private var emailValid: Bool { AuthService.isValidEmail(email) }

    private var passwordLengthMet: Bool { (8...20).contains(password.count) }
    private var passwordUppercaseMet: Bool { password.contains(where: \.isUppercase) }
    private var passwordLowercaseMet: Bool { password.contains(where: \.isLowercase) }
    private var passwordNumberMet: Bool { password.contains(where: \.isNumber) }
    /// True once the confirmation matches a non-empty password.
    private var passwordsMatch: Bool { !confirmPassword.isEmpty && password == confirmPassword }

    /// Every rule satisfied — gates the Create account button.
    private var allPasswordRequirementsMet: Bool {
        passwordLengthMet && passwordUppercaseMet && passwordLowercaseMet
            && passwordNumberMet && passwordsMatch
    }

    /// The live checklist shown under the password fields on sign-up; each row
    /// ticks green the moment its rule is met.
    private var passwordRequirements: some View {
        VStack(alignment: .leading, spacing: DreamMetric.xs) {
            requirementRow("8–20 characters", met: passwordLengthMet)
            requirementRow("An uppercase letter", met: passwordUppercaseMet)
            requirementRow("A lowercase letter", met: passwordLowercaseMet)
            requirementRow("A number", met: passwordNumberMet)
            requirementRow("Passwords match", met: passwordsMatch)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DreamMetric.xs)
    }

    private func requirementRow(_ text: String, met: Bool) -> some View {
        HStack(spacing: DreamMetric.xs) {
            Image(systemName: met ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 13))
                .foregroundStyle(met ? .green : Color.dreamText.opacity(0.3))
            Text(text)
                .font(.dreamBody(12, .medium))
                .foregroundStyle(met ? Color.dreamText.opacity(0.8) : .secondary)
        }
        .animation(.easeOut(duration: 0.15), value: met)
    }

    private func field(_ placeholder: String, text: Binding<String>, isSecure: Bool, contentType: UITextContentType? = nil) -> some View {
        Group {
            if isSecure {
                SecureField(placeholder, text: text)
                    .textContentType(contentType)
            } else {
                TextField(placeholder, text: text)
                    .textContentType(contentType)
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
        // The button's style plays the press tap; only the error needs a sound.
        Task {
            switch mode {
            case .signUp:
                guard password == confirmPassword else {
                    auth.errorMessage = "Passwords don't match."
                    SoundManager.shared.play(.wrong)
                    return
                }
                await auth.signUp(
                    email: email,
                    password: password,
                    username: username,
                    firstName: firstName,
                    lastName: lastName
                )
            case .signIn:
                await auth.signIn(email: email, password: password)
            }
        }
    }
}

// MARK: - Sign in with Apple

/// The Apple sign-in control, in its own view so it isn't rebuilt on every
/// keystroke in the form above (it bridges to a UIKit control, which is the
/// expensive part). Its inputs never change, so SwiftUI skips re-evaluating it
/// when the parent re-renders for unrelated state.
private struct AppleSignInButton: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        SignInWithAppleButton(.continue) { request in
            auth.prepareAppleRequest(request)
        } onCompletion: { result in
            Task { await auth.completeAppleSignIn(result) }
        }
        .signInWithAppleButtonStyle(scheme == .dark ? .white : .black)
        .frame(height: 50)
        .clipShape(.rect(cornerRadius: DreamMetric.controlRadius))
    }
}

// MARK: - Forgot password

/// A dedicated screen for requesting a password-reset email. Pushed from the
/// sign-in / sign-up form; carries over whatever email was already typed.
struct ForgotPasswordView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State var email: String
    @FocusState private var emailFocused: Bool

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
                    .focused($emailFocused)

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
        .toolbar {
            // A Done button above the keyboard to dismiss it from the email field.
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { emailFocused = false }
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.dreamPrimary)
            }
        }
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
