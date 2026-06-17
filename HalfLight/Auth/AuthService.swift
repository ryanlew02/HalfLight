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

/// A signed-in account, identified by email (display only).
protocol AuthBackend: Sendable {
    func currentEmail() async -> String?
    func currentProvider() async -> AuthProvider?
    func signUp(email: String, password: String) async throws -> String
    func signIn(email: String, password: String) async throws -> String
    func signInWithApple(idToken: String, nonce: String, email: String?) async throws -> String
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
    var isWorking = false
    var errorMessage: String?
    /// A transient success message (e.g. password-reset confirmation).
    var infoMessage: String?

    private let backend: AuthBackend
    /// Raw nonce shared between the Apple request and its completion.
    private var appleNonce: String?

    var isSignedIn: Bool { status == .signedIn }

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
    }

    func signUp(email: String, password: String) async {
        await perform(provider: .email) { try await self.backend.signUp(email: email, password: password) }
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
            await perform(provider: .apple) {
                try await self.backend.signInWithApple(idToken: idToken, nonce: nonce, email: appleEmail)
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

    func currentEmail() async -> String? {
        UserDefaults.standard.string(forKey: key)
    }

    func currentProvider() async -> AuthProvider? {
        UserDefaults.standard.string(forKey: providerKey).flatMap(AuthProvider.init(rawValue:))
    }

    func signUp(email: String, password: String) async throws -> String {
        try validate(email: email, password: password)
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
/// Real backend backed by Supabase Auth. Note: exact API names can vary slightly
/// between supabase-swift versions — adjust here if the compiler flags them.
final class SupabaseAuthBackend: AuthBackend {
    private let client = SupabaseClient(
        supabaseURL: SupabaseConfig.url,
        supabaseKey: SupabaseConfig.anonKey
    )

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

    func signUp(email: String, password: String) async throws -> String {
        guard SupabaseConfig.isConfigured else { throw notConfigured }
        let response = try await client.auth.signUp(email: email, password: password)
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

    func sendPasswordReset(email: String) async throws {
        guard SupabaseConfig.isConfigured else { throw notConfigured }
        try await client.auth.resetPasswordForEmail(email)
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
