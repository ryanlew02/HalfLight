//
//  AuthService.swift
//  HalfLight
//
//  Authentication layer. The app talks to `AuthService` (an @Observable injected
//  into the environment); the actual network calls live behind `AuthBackend`.
//
//  Until the `supabase-swift` package is added to the project this falls back to
//  a local `MockAuthBackend` so the UI is fully testable. Once the package is
//  present, `#if canImport(Supabase)` swaps in the real `SupabaseAuthBackend`.
//

import Foundation
import AuthenticationServices
import CryptoKit

#if canImport(Supabase)
import Supabase
#endif

// MARK: - Backend abstraction

/// How the current account authenticates. Used to hide password management for
/// accounts that don't have a password (e.g. Sign in with Apple).
enum AuthProvider: String, Sendable {
    case email
    case apple
    case unknown
}

/// A user's public profile. `firstName`/`lastName` may be empty when only the
/// username could be fetched (names are kept private on the server).
struct ProfileInfo: Sendable {
    let username: String
    let firstName: String
    let lastName: String
}

/// A signed-in account, identified by email (display only).
protocol AuthBackend: Sendable {
    func currentEmail() async -> String?
    func currentProvider() async -> AuthProvider?
    /// Whether a username isn't already taken (checked case-insensitively).
    func isUsernameAvailable(_ username: String) async throws -> Bool
    func signUp(
        email: String,
        password: String,
        username: String,
        firstName: String,
        lastName: String
    ) async throws -> String
    func signIn(email: String, password: String) async throws -> String
    func signInWithApple(idToken: String, nonce: String, email: String?) async throws -> String
    /// Create the profile row for the currently signed-in user (used to finish
    /// onboarding accounts that didn't pick a username at sign-up, e.g. Apple).
    func createProfile(username: String, firstName: String, lastName: String) async throws
    /// The current user's existing profile, if any (so returning users aren't
    /// asked to choose a username again).
    func fetchProfile() async -> ProfileInfo?
    func sendPasswordReset(email: String) async throws
    func changePassword(currentPassword: String, newPassword: String) async throws
    func signOut() async throws
}

enum AuthError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): text }
    }
}

// MARK: - Observable service

@MainActor
@Observable
final class AuthService {
    enum Status: Equatable { case unknown, signedOut, signedIn }

    private(set) var status: Status = .unknown
    private(set) var email: String?
    private(set) var provider: AuthProvider = .unknown
    private(set) var username: String?
    private(set) var firstName: String?
    private(set) var lastName: String?
    var isWorking = false
    var errorMessage: String?
    /// A transient success message (e.g. password-reset confirmation).
    var infoMessage: String?

    private let backend: AuthBackend
    /// Raw nonce shared between the Apple request and its completion.
    private var appleNonce: String?

    var isSignedIn: Bool { status == .signedIn }

    /// Signed in but without a username yet — the app gates onboarding on this.
    var needsProfileSetup: Bool { isSignedIn && (username?.isEmpty ?? true) }

    /// Only email/password accounts can change their password in-app; Apple
    /// accounts don't have one to manage.
    var canChangePassword: Bool { isSignedIn && provider == .email }

    init(backend: AuthBackend? = nil) {
        if let backend {
            self.backend = backend
        } else {
            #if canImport(Supabase)
            self.backend = SupabaseAuthBackend()
            #else
            self.backend = MockAuthBackend()
            #endif
        }
    }

    /// Restore any persisted session at launch.
    func restore() async {
        let email = await backend.currentEmail()
        self.email = email
        provider = (email == nil) ? .unknown : (await backend.currentProvider() ?? .unknown)
        status = (email == nil) ? .signedOut : .signedIn
        let defaults = UserDefaults.standard
        username = defaults.string(forKey: "userUsername")
        firstName = defaults.string(forKey: "userFirstName")
        lastName = defaults.string(forKey: "userLastName")
        // Reinstall / new device: pull the username from the server so an existing
        // account isn't asked to choose one again.
        await hydrateProfileIfNeeded()
    }

    /// If signed in but no username is known locally, fetch it from the backend
    /// and cache it. Leaves names untouched when the server doesn't return them.
    private func hydrateProfileIfNeeded() async {
        guard isSignedIn, (username?.isEmpty ?? true) else { return }
        guard let remote = await backend.fetchProfile() else { return }
        let defaults = UserDefaults.standard
        username = remote.username
        defaults.set(remote.username, forKey: "userUsername")
        if !remote.firstName.isEmpty {
            firstName = remote.firstName
            defaults.set(remote.firstName, forKey: "userFirstName")
            defaults.set(remote.firstName, forKey: "userName")
        }
        if !remote.lastName.isEmpty {
            lastName = remote.lastName
            defaults.set(remote.lastName, forKey: "userLastName")
        }
    }

    /// Finish onboarding for an account with no username yet (e.g. Sign in with
    /// Apple). Validates, checks uniqueness, writes the profile, and lifts the gate.
    /// Returns `true` on success.
    @discardableResult
    func completeProfile(username: String, firstName: String, lastName: String) async -> Bool {
        isWorking = true
        errorMessage = nil
        infoMessage = nil
        defer { isWorking = false }

        let handle = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let first = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = lastName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !first.isEmpty, !last.isEmpty else {
            errorMessage = "Please enter your first and last name."
            return false
        }
        guard Self.isValidUsername(handle) else {
            errorMessage = "Usernames must be 3–20 characters using letters, numbers, or underscores."
            return false
        }
        do {
            guard try await backend.isUsernameAvailable(handle) else {
                errorMessage = "“\(handle)” is taken. Try another username."
                return false
            }
            try await backend.createProfile(username: handle, firstName: first, lastName: last)
            persistProfile(username: handle, firstName: first, lastName: last)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Create an account with a unique username and the dreamer's name.
    func signUp(
        email: String,
        password: String,
        username: String,
        firstName: String,
        lastName: String
    ) async {
        isWorking = true
        errorMessage = nil
        infoMessage = nil
        defer { isWorking = false }

        let handle = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let first = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = lastName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !first.isEmpty, !last.isEmpty else {
            errorMessage = "Please enter your first and last name."
            return
        }
        guard Self.isValidUsername(handle) else {
            errorMessage = "Usernames must be 3–20 characters using letters, numbers, or underscores."
            return
        }

        do {
            guard try await backend.isUsernameAvailable(handle) else {
                errorMessage = "“\(handle)” is taken. Try another username."
                return
            }
            let resolvedEmail = try await backend.signUp(
                email: email,
                password: password,
                username: handle,
                firstName: first,
                lastName: last
            )
            persistProfile(username: handle, firstName: first, lastName: last)
            self.email = resolvedEmail
            self.provider = .email
            status = .signedIn
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Persist profile fields locally so they survive relaunch and personalize the
    /// app (the greeting reads `userName`).
    private func persistProfile(username: String, firstName: String, lastName: String) {
        let defaults = UserDefaults.standard
        defaults.set(username, forKey: "userUsername")
        defaults.set(firstName, forKey: "userFirstName")
        defaults.set(lastName, forKey: "userLastName")
        defaults.set(firstName, forKey: "userName")
        self.username = username
        self.firstName = firstName
        self.lastName = lastName
    }

    /// Usernames: 3–20 chars, lowercase letters, numbers, or underscores.
    static func isValidUsername(_ username: String) -> Bool {
        username.range(of: "^[a-z0-9_]{3,20}$", options: .regularExpression) != nil
    }

    func signIn(email: String, password: String) async {
        await perform(provider: .email) { try await self.backend.signIn(email: email, password: password) }
    }

    func sendPasswordReset(email: String) async {
        isWorking = true
        errorMessage = nil
        infoMessage = nil
        defer { isWorking = false }
        do {
            try await backend.sendPasswordReset(email: email)
            infoMessage = "We've emailed a password reset link to \(email)."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Returns `true` on success so the caller can clear fields / dismiss.
    @discardableResult
    func changePassword(current: String, new: String) async -> Bool {
        isWorking = true
        errorMessage = nil
        infoMessage = nil
        defer { isWorking = false }
        do {
            try await backend.changePassword(currentPassword: current, newPassword: new)
            infoMessage = "Your password has been updated."
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func signOut() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await backend.signOut()
            email = nil
            provider = .unknown
            status = .signedOut
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Sign in with Apple

    /// Configure the Apple ID request with a fresh, hashed nonce.
    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonce()
        appleNonce = nonce
        request.requestedScopes = [.email, .fullName]
        request.nonce = Self.sha256(nonce)
    }

    /// Handle the result of the Sign in with Apple flow.
    func completeAppleSignIn(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let error):
            // A user cancelling shouldn't read as an error.
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            errorMessage = error.localizedDescription
        case .success(let authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let idToken = String(data: tokenData, encoding: .utf8),
                let nonce = appleNonce
            else {
                errorMessage = "Couldn't read your Apple credentials. Please try again."
                return
            }
            let appleEmail = credential.email
            let appleName = credential.fullName
            await perform(provider: .apple) {
                try await self.backend.signInWithApple(idToken: idToken, nonce: nonce, email: appleEmail)
            }
            // Pull an existing profile if there is one; otherwise prefill the
            // username-setup screen with the name Apple just gave us (first sign-in
            // only — Apple won't send it again).
            await hydrateProfileIfNeeded()
            if needsProfileSetup {
                if let given = appleName?.givenName, (firstName?.isEmpty ?? true) {
                    firstName = given
                }
                if let family = appleName?.familyName, (lastName?.isEmpty ?? true) {
                    lastName = family
                }
            }
        }
    }

    // MARK: Internals

    private func perform(provider: AuthProvider, _ work: @escaping () async throws -> String) async {
        isWorking = true
        errorMessage = nil
        infoMessage = nil
        defer { isWorking = false }
        do {
            let email = try await work()
            self.email = email
            self.provider = provider
            status = .signedIn
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func randomNonce(length: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        let result = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        precondition(result == errSecSuccess, "Unable to generate nonce.")
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

// MARK: - Local mock (used until the Supabase SDK is added)

/// A stand-in backend that persists a "signed-in" email in UserDefaults so the
/// auth UI and session restore can be exercised without a network/backend.
final class MockAuthBackend: AuthBackend {
    private let key = "mockAuthEmail"
    private let providerKey = "mockAuthProvider"
    private let usernamesKey = "mockTakenUsernames"

    func currentEmail() async -> String? {
        UserDefaults.standard.string(forKey: key)
    }

    func currentProvider() async -> AuthProvider? {
        UserDefaults.standard.string(forKey: providerKey).flatMap(AuthProvider.init(rawValue:))
    }

    func isUsernameAvailable(_ username: String) async throws -> Bool {
        let taken = Set(UserDefaults.standard.stringArray(forKey: usernamesKey) ?? [])
        return !taken.contains(username.lowercased())
    }

    func signUp(
        email: String,
        password: String,
        username: String,
        firstName: String,
        lastName: String
    ) async throws -> String {
        try validate(email: email, password: password)
        var taken = Set(UserDefaults.standard.stringArray(forKey: usernamesKey) ?? [])
        guard taken.insert(username.lowercased()).inserted else {
            throw AuthError.message("“\(username)” is taken. Try another username.")
        }
        UserDefaults.standard.set(Array(taken), forKey: usernamesKey)
        UserDefaults.standard.set(email, forKey: key)
        UserDefaults.standard.set(AuthProvider.email.rawValue, forKey: providerKey)
        return email
    }

    func signIn(email: String, password: String) async throws -> String {
        try validate(email: email, password: password)
        UserDefaults.standard.set(email, forKey: key)
        UserDefaults.standard.set(AuthProvider.email.rawValue, forKey: providerKey)
        return email
    }

    func signInWithApple(idToken: String, nonce: String, email: String?) async throws -> String {
        let resolved = email ?? "you@icloud.com"
        UserDefaults.standard.set(resolved, forKey: key)
        UserDefaults.standard.set(AuthProvider.apple.rawValue, forKey: providerKey)
        return resolved
    }

    func createProfile(username: String, firstName: String, lastName: String) async throws {
        var taken = Set(UserDefaults.standard.stringArray(forKey: usernamesKey) ?? [])
        guard taken.insert(username.lowercased()).inserted else {
            throw AuthError.message("“\(username)” is taken. Try another username.")
        }
        UserDefaults.standard.set(Array(taken), forKey: usernamesKey)
    }

    func fetchProfile() async -> ProfileInfo? {
        // No real server in the mock — same-device username persists locally.
        nil
    }

    func sendPasswordReset(email: String) async throws {
        guard email.contains("@"), email.contains(".") else {
            throw AuthError.message("Please enter a valid email address.")
        }
        // No-op in the mock — pretend the email was sent.
    }

    func changePassword(currentPassword: String, newPassword: String) async throws {
        guard newPassword.count >= 6 else {
            throw AuthError.message("New password must be at least 6 characters.")
        }
        // No stored password in the mock — pretend the update succeeded.
    }

    func signOut() async throws {
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.removeObject(forKey: providerKey)
    }

    private func validate(email: String, password: String) throws {
        guard email.contains("@"), email.contains(".") else {
            throw AuthError.message("Please enter a valid email address.")
        }
        guard password.count >= 6 else {
            throw AuthError.message("Password must be at least 6 characters.")
        }
    }
}

// MARK: - Supabase backend (active once the package is added)

#if canImport(Supabase)
/// A row in the `profiles` table that mirrors an auth user's public details.
private struct ProfileRow: Codable {
    let id: UUID
    let username: String
    let firstName: String
    let lastName: String

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case firstName = "first_name"
        case lastName = "last_name"
    }
}

/// Minimal row for username-only reads (names are kept private server-side).
private struct UsernameRow: Codable {
    let username: String
}

/// Real backend backed by Supabase Auth. Note: exact API names can vary slightly
/// between supabase-swift versions — adjust here if the compiler flags them.
final class SupabaseAuthBackend: AuthBackend {
    // Shared with DreamSync so auth session and dream backup use the same JWT.
    private var client: SupabaseClient { SupabaseClientProvider.shared }

    func currentEmail() async -> String? {
        (try? await client.auth.session)?.user.email
    }

    func currentProvider() async -> AuthProvider? {
        guard let user = (try? await client.auth.session)?.user else { return nil }
        // Supabase records the sign-in method in app_metadata.provider.
        if case let .string(value)? = user.appMetadata["provider"] {
            return AuthProvider(rawValue: value) ?? .unknown
        }
        return .unknown
    }

    func isUsernameAvailable(_ username: String) async throws -> Bool {
        guard SupabaseConfig.isConfigured else { throw notConfigured }
        // Requires a `profiles` table with a unique, lowercase `username` column.
        let rows: [ProfileRow] = try await client
            .from("profiles")
            .select("username")
            .eq("username", value: username)
            .limit(1)
            .execute()
            .value
        return rows.isEmpty
    }

    func signUp(
        email: String,
        password: String,
        username: String,
        firstName: String,
        lastName: String
    ) async throws -> String {
        guard SupabaseConfig.isConfigured else { throw notConfigured }
        let response = try await client.auth.signUp(
            email: email,
            password: password,
            data: [
                "username": .string(username),
                "first_name": .string(firstName),
                "last_name": .string(lastName)
            ]
        )
        // Supabase doesn't error on a duplicate email when confirmations are on
        // (it avoids leaking which emails exist); instead it returns a user with
        // an empty `identities` array. Treat that as "already registered".
        if let identities = response.user.identities, identities.isEmpty {
            throw AuthError.message("An account with this email already exists. Try resetting your password instead.")
        }
        // Persist the profile row. The DB's unique constraint on `username` is the
        // source of truth — if two people race for the same name, the insert fails.
        do {
            try await client
                .from("profiles")
                .insert(ProfileRow(
                    id: response.user.id,
                    username: username,
                    firstName: firstName,
                    lastName: lastName
                ))
                .execute()
        } catch {
            throw AuthError.message("“\(username)” was just taken. Try another username.")
        }
        return response.user.email ?? email
    }

    func signIn(email: String, password: String) async throws -> String {
        guard SupabaseConfig.isConfigured else { throw notConfigured }
        let session = try await client.auth.signIn(email: email, password: password)
        return session.user.email ?? email
    }

    func signInWithApple(idToken: String, nonce: String, email: String?) async throws -> String {
        guard SupabaseConfig.isConfigured else { throw notConfigured }
        let session = try await client.auth.signInWithIdToken(
            credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
        )
        return session.user.email ?? email ?? ""
    }

    func createProfile(username: String, firstName: String, lastName: String) async throws {
        guard SupabaseConfig.isConfigured else { throw notConfigured }
        guard let userID = (try? await client.auth.session)?.user.id else {
            throw AuthError.message("You need to be signed in to choose a username.")
        }
        do {
            try await client
                .from("profiles")
                .insert(ProfileRow(id: userID, username: username, firstName: firstName, lastName: lastName))
                .execute()
        } catch {
            throw AuthError.message("“\(username)” was just taken. Try another username.")
        }
    }

    func fetchProfile() async -> ProfileInfo? {
        guard SupabaseConfig.isConfigured,
              let userID = (try? await client.auth.session)?.user.id else { return nil }
        let rows: [UsernameRow]? = try? await client
            .from("profiles")
            .select("username")
            .eq("id", value: userID)
            .limit(1)
            .execute()
            .value
        guard let username = rows?.first?.username else { return nil }
        // Names stay private on the server; the gate only needs the username.
        return ProfileInfo(username: username, firstName: "", lastName: "")
    }

    func sendPasswordReset(email: String) async throws {
        guard SupabaseConfig.isConfigured else { throw notConfigured }
        // When a redirect is configured (and allowlisted in the dashboard), the
        // email link returns the user to the app instead of the Site URL.
        if let redirect = SupabaseConfig.passwordResetRedirect {
            try await client.auth.resetPasswordForEmail(email, redirectTo: redirect)
        } else {
            try await client.auth.resetPasswordForEmail(email)
        }
    }

    func changePassword(currentPassword: String, newPassword: String) async throws {
        guard SupabaseConfig.isConfigured else { throw notConfigured }
        guard let email = (try? await client.auth.session)?.user.email else {
            throw AuthError.message("You need to be signed in to change your password.")
        }
        // Verify the current password by re-authenticating, then update.
        do {
            _ = try await client.auth.signIn(email: email, password: currentPassword)
        } catch {
            throw AuthError.message("Your current password is incorrect.")
        }
        try await client.auth.update(user: UserAttributes(password: newPassword))
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }

    private var notConfigured: AuthError {
        .message("Supabase isn't configured yet — add your project URL and anon key in SupabaseConfig.swift.")
    }
}
#endif
