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
/// username could be fetched (names are kept private on the server). `bio` is
/// free-text and may be empty.
struct ProfileInfo: Sendable {
    let username: String
    let firstName: String
    let lastName: String
    let bio: String
    /// When the username was last changed, used to enforce the 30-day cooldown.
    /// `nil` when it has never been changed since sign-up.
    let usernameChangedAt: Date?
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
    /// Update the current user's bio (free-text; may be empty to clear it).
    func updateBio(_ bio: String) async throws
    /// Store the current user's profile photo (cropped JPEG), or clear it with
    /// `nil`, so it syncs across their devices.
    func updateAvatar(_ data: Data?) async throws
    /// The current user's profile photo, if one has been uploaded.
    func fetchAvatar() async -> Data?
    /// Change the current user's username. Throws if it's taken or the server's
    /// 30-day cooldown rejects it.
    func updateUsername(_ username: String) async throws
    func sendPasswordReset(email: String) async throws
    func changePassword(currentPassword: String, newPassword: String) async throws
    func signOut() async throws
    /// Permanently delete the current user's account and all server-side data.
    func deleteAccount() async throws
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
    private(set) var bio: String?
    /// When the username was last changed (drives the 30-day cooldown).
    private(set) var usernameChangedAt: Date?
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

    /// How long a username must stay put after a change.
    static let usernameCooldown: TimeInterval = 30 * 24 * 60 * 60

    /// When the 30-day username cooldown ends, or `nil` if the username can be
    /// changed right now.
    var usernameCooldownEnds: Date? {
        guard let changed = usernameChangedAt else { return nil }
        let ends = changed.addingTimeInterval(Self.usernameCooldown)
        return ends > Date() ? ends : nil
    }

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
        bio = defaults.string(forKey: "userBio")
        usernameChangedAt = defaults.object(forKey: "userUsernameChangedAt") as? Date
        // Reinstall / new device: pull the username from the server so an existing
        // account isn't asked to choose one again.
        await hydrateProfileIfNeeded()
        await hydrateAvatarIfNeeded()
    }

    /// Keep the local profile photo and the account's copy in step:
    /// - no local photo → pull the account's, so it follows the dreamer to a new
    ///   device;
    /// - local photo but none on the account → upload it (backfills photos set
    ///   before cross-device sync existed).
    private func hydrateAvatarIfNeeded() async {
        guard isSignedIn else { return }
        if let local = UserDefaults.standard.data(forKey: "profilePhoto") {
            if await backend.fetchAvatar() == nil {
                try? await backend.updateAvatar(local)
            }
        } else if let remote = await backend.fetchAvatar() {
            UserDefaults.standard.set(remote, forKey: "profilePhoto")
        }
    }

    /// Upload (or clear, with `nil`) the dreamer's profile photo to their account.
    /// Best-effort, mirroring the dream/feed sync: the local copy is the source of
    /// truth and a failed upload simply retries next time the photo changes.
    func updateAvatar(_ data: Data?) async {
        try? await backend.updateAvatar(data)
    }

    /// Refresh the cached profile from the account whenever signed in: the server
    /// is the source of truth for a signed-in dreamer, so this also makes the
    /// account's first name win over any locally-set name (the greeting reads
    /// `userName`). Runs on every launch / sign-in; a failed fetch (e.g. offline)
    /// leaves the cached values in place.
    private func hydrateProfileIfNeeded() async {
        guard isSignedIn else { return }
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
        // Bio is free-text; an empty value is a valid "no bio yet" state.
        bio = remote.bio
        defaults.set(remote.bio, forKey: "userBio")
        if let changed = remote.usernameChangedAt {
            usernameChangedAt = changed
            defaults.set(changed, forKey: "userUsernameChangedAt")
        } else {
            usernameChangedAt = nil
            defaults.removeObject(forKey: "userUsernameChangedAt")
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

    /// Save the dreamer's bio to their profile. Trims whitespace; an empty string
    /// clears the bio. Returns `true` on success so the caller can dismiss.
    @discardableResult
    func updateBio(_ newBio: String) async -> Bool {
        isWorking = true
        errorMessage = nil
        infoMessage = nil
        defer { isWorking = false }

        let trimmed = newBio.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await backend.updateBio(trimmed)
            bio = trimmed
            UserDefaults.standard.set(trimmed, forKey: "userBio")
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Change the dreamer's username. Validates format, the 30-day cooldown, and
    /// uniqueness before writing. Returns `true` on success (or if unchanged).
    @discardableResult
    func updateUsername(_ newUsername: String) async -> Bool {
        isWorking = true
        errorMessage = nil
        infoMessage = nil
        defer { isWorking = false }

        let handle = newUsername.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Nothing to do if it didn't actually change.
        if handle == username { return true }

        guard Self.isValidUsername(handle) else {
            errorMessage = "Usernames must be 3–20 characters using letters, numbers, or underscores."
            return false
        }
        if usernameCooldownEnds != nil {
            errorMessage = "You can only change your username once every 30 days."
            return false
        }
        do {
            guard try await backend.isUsernameAvailable(handle) else {
                errorMessage = "“\(handle)” is taken. Try another username."
                return false
            }
            try await backend.updateUsername(handle)
            let now = Date()
            username = handle
            usernameChangedAt = now
            let defaults = UserDefaults.standard
            defaults.set(handle, forKey: "userUsername")
            defaults.set(now, forKey: "userUsernameChangedAt")
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
        // New device: pull the profile + photo so they're present immediately.
        await hydrateProfileIfNeeded()
        await hydrateAvatarIfNeeded()
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
            // Drop the cached photo so the next account doesn't inherit it (and so
            // its own photo can hydrate from the server).
            UserDefaults.standard.removeObject(forKey: "profilePhoto")
            email = nil
            provider = .unknown
            status = .signedOut
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Permanently delete the account and all its server-side data, then drop to
    /// the signed-out state. Returns `true` on success.
    @discardableResult
    func deleteAccount() async -> Bool {
        isWorking = true
        errorMessage = nil
        infoMessage = nil
        defer { isWorking = false }
        do {
            try await backend.deleteAccount()
            clearPersistedProfile()
            email = nil
            provider = .unknown
            username = nil
            firstName = nil
            lastName = nil
            bio = nil
            usernameChangedAt = nil
            status = .signedOut
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Drop the locally-cached profile fields after sign-out / deletion.
    private func clearPersistedProfile() {
        let defaults = UserDefaults.standard
        for key in [
            "userUsername", "userFirstName", "userLastName",
            "userName", "userBio", "userUsernameChangedAt", "profilePhoto",
        ] {
            defaults.removeObject(forKey: key)
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
            await hydrateAvatarIfNeeded()
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

    func updateBio(_ bio: String) async throws {
        UserDefaults.standard.set(bio, forKey: "mockBio")
    }

    func updateAvatar(_ data: Data?) async throws {
        if let data { UserDefaults.standard.set(data, forKey: "mockAvatar") }
        else { UserDefaults.standard.removeObject(forKey: "mockAvatar") }
    }

    func fetchAvatar() async -> Data? {
        UserDefaults.standard.data(forKey: "mockAvatar")
    }

    func updateUsername(_ username: String) async throws {
        var taken = Set(UserDefaults.standard.stringArray(forKey: usernamesKey) ?? [])
        guard taken.insert(username.lowercased()).inserted else {
            throw AuthError.message("“\(username)” is taken. Try another username.")
        }
        UserDefaults.standard.set(Array(taken), forKey: usernamesKey)
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

    func deleteAccount() async throws {
        // No real backend — just drop the mock's signed-in state.
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

/// The caller's own full profile, returned by the `my_profile()` RPC (names are
/// private from other users but visible to their owner).
private struct MyProfileRow: Decodable {
    let username: String
    let firstName: String?
    let lastName: String?
    let bio: String?
    /// Raw timestamptz text; parsed into a `Date` by the backend.
    let usernameChangedAt: String?

    enum CodingKeys: String, CodingKey {
        case username
        case firstName = "first_name"
        case lastName = "last_name"
        case bio
        case usernameChangedAt = "username_changed_at"
    }
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
              (try? await client.auth.session) != nil else { return nil }
        // `my_profile()` returns the caller's own row including their name, which
        // is private from everyone else — so the app can greet returning users by
        // their account first name on any device.
        let rows: [MyProfileRow]? = try? await client
            .rpc("my_profile")
            .execute()
            .value
        guard let row = rows?.first else { return nil }
        return ProfileInfo(
            username: row.username,
            firstName: row.firstName ?? "",
            lastName: row.lastName ?? "",
            bio: row.bio ?? "",
            usernameChangedAt: row.usernameChangedAt.flatMap(Self.parseTimestamp)
        )
    }

    func updateBio(_ bio: String) async throws {
        guard SupabaseConfig.isConfigured else { throw notConfigured }
        guard let userID = (try? await client.auth.session)?.user.id else {
            throw AuthError.message("You need to be signed in to edit your profile.")
        }
        try await client
            .from("profiles")
            .update(["bio": bio])
            .eq("id", value: userID)
            .execute()
    }

    func updateAvatar(_ data: Data?) async throws {
        guard SupabaseConfig.isConfigured else { throw notConfigured }
        guard let userID = (try? await client.auth.session)?.user.id else {
            throw AuthError.message("You need to be signed in to update your photo.")
        }
        // A Codable struct (rather than a dictionary) so a `nil` encodes as SQL
        // NULL, clearing the column when the photo is removed.
        struct AvatarUpdate: Encodable { let avatar: String? }
        try await client
            .from("profiles")
            .update(AvatarUpdate(avatar: data?.base64EncodedString()))
            .eq("id", value: userID)
            .execute()
    }

    func fetchAvatar() async -> Data? {
        guard SupabaseConfig.isConfigured,
              let userID = (try? await client.auth.session)?.user.id else { return nil }
        struct AvatarRow: Decodable { let avatar: String? }
        let rows: [AvatarRow]? = try? await client
            .from("profiles")
            .select("avatar")
            .eq("id", value: userID)
            .limit(1)
            .execute()
            .value
        guard let encoded = rows?.first?.avatar else { return nil }
        return Data(base64Encoded: encoded)
    }

    func updateUsername(_ username: String) async throws {
        guard SupabaseConfig.isConfigured else { throw notConfigured }
        guard let userID = (try? await client.auth.session)?.user.id else {
            throw AuthError.message("You need to be signed in to change your username.")
        }
        do {
            try await client
                .from("profiles")
                .update(["username": username])
                .eq("id", value: userID)
                .execute()
        } catch {
            // Either the unique constraint (taken) or the cooldown trigger fired.
            throw AuthError.message("Couldn't change your username — it may be taken, or you changed it within the last 30 days.")
        }
    }

    /// Parse a Postgres `timestamptz` string (e.g. with microsecond precision)
    /// into a `Date`, tolerating fractional seconds the ISO formatter rejects.
    private static func parseTimestamp(_ value: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: value) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: value) { return date }
        // Strip fractional seconds (Postgres emits up to 6 digits) and retry.
        if let dot = value.range(of: #"\.\d+"#, options: .regularExpression) {
            var trimmed = value
            trimmed.removeSubrange(dot)
            return iso.date(from: trimmed)
        }
        return nil
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

    func deleteAccount() async throws {
        guard SupabaseConfig.isConfigured else { throw notConfigured }
        guard let token = (try? await client.auth.session)?.accessToken else {
            throw AuthError.message("You need to be signed in to delete your account.")
        }
        // Account deletion needs the service-role key, which must never ship in
        // the app — so it runs in the `delete-account` edge function. We just
        // call it with the user's access token; it verifies and deletes them.
        let endpoint = SupabaseConfig.url.appendingPathComponent("functions/v1/delete-account")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            if let payload = try? JSONDecoder().decode([String: String].self, from: data),
               let message = payload["error"] {
                throw AuthError.message(message)
            }
            throw AuthError.message("Couldn't delete your account. Please try again.")
        }
        // The account is gone; clear the now-invalid local session.
        try? await client.auth.signOut()
    }

    private var notConfigured: AuthError {
        .message("Supabase isn't configured yet — add your project URL and anon key in SupabaseConfig.swift.")
    }
}
#endif
