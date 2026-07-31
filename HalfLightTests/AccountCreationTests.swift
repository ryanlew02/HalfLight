//
//  AccountCreationTests.swift
//  HalfLightTests
//
//  Stress-tests the two ways an account comes into existence: email/password
//  sign-up and Sign in with Apple.
//
//  The validators are the interesting part. `isValidUsername` is mirrored
//  character-for-character by a Postgres trigger (see the username_validation
//  migration), so the boundary cases below double as a guard against the two
//  drifting apart — a drift shows up as a user who passes the form and is then
//  rejected by the server with a raw database error.
//
//  The flow tests drive `AuthService` through a stub backend so the paths that
//  only happen against a real server — email confirmation, a lost username race,
//  a returning Apple user who gets no name — can be exercised deterministically.
//

import XCTest
import AuthenticationServices
@testable import HalfLight

@MainActor
final class AccountCreationTests: XCTestCase {

    private let defaultsKeys = [
        "mockAuthEmail", "mockAuthProvider", "mockTakenUsernames",
        "userUsername", "userFirstName", "userLastName", "userName",
    ]

    override func setUp() {
        super.setUp()
        defaultsKeys.forEach(UserDefaults.standard.removeObject(forKey:))
    }

    override func tearDown() {
        defaultsKeys.forEach(UserDefaults.standard.removeObject(forKey:))
        super.tearDown()
    }

    // MARK: - Username validation

    func testUsernameLengthBoundaries() {
        XCTAssertFalse(AuthService.isValidUsername(""))
        XCTAssertFalse(AuthService.isValidUsername("ab"), "2 chars is below the floor")
        XCTAssertTrue(AuthService.isValidUsername("abc"), "3 chars is the floor")
        XCTAssertTrue(AuthService.isValidUsername(String(repeating: "a", count: 20)))
        XCTAssertFalse(AuthService.isValidUsername(String(repeating: "a", count: 21)))
        XCTAssertFalse(AuthService.isValidUsername(String(repeating: "a", count: 200)))
    }

    func testUsernameRejectsAnythingOutsideTheAllowedSet() {
        // Each of these landed in the profiles table during an earlier stress
        // pass, which is why the rule is now enforced in Postgres too.
        let rejected = [
            "Dreamer",                  // uppercase
            "dream er",                 // space
            "dream-er",                 // hyphen
            "dream.er",                 // dot
            "dream@er",                 // at
            "💀admin💀",                 // emoji
            "<script>alert(1)</script>",
            "'; drop table profiles;--",
            "admin\u{0000}",            // null byte
            "user\u{202E}nimda",        // RTL override
            "\u{0430}dmin",             // Cyrillic homoglyph 'а'
            "ünïcode",
            "  spaced  ",
            "\n",
            "%s%s%s",
        ]
        for handle in rejected {
            XCTAssertFalse(
                AuthService.isValidUsername(handle),
                "expected \(handle.debugDescription) to be rejected"
            )
        }
    }

    func testUsernameAcceptsTheFullAllowedAlphabet() {
        XCTAssertTrue(AuthService.isValidUsername("abcdefghijklmnopqrst"))
        XCTAssertTrue(AuthService.isValidUsername("user_123"))
        XCTAssertTrue(AuthService.isValidUsername("___"))
        XCTAssertTrue(AuthService.isValidUsername("000"))
    }

    /// The client regex and the Postgres trigger must stay identical.
    func testUsernameRuleMatchesTheDatabaseRegex() {
        let databaseRegex = "^[a-z0-9_]{3,20}$"
        let samples = [
            "abc", "ab", "user_123", "Dreamer", "___", "💀admin💀",
            String(repeating: "a", count: 20), String(repeating: "a", count: 21),
        ]
        for sample in samples {
            let serverWouldAccept = sample.range(of: databaseRegex, options: .regularExpression) != nil
            XCTAssertEqual(
                AuthService.isValidUsername(sample), serverWouldAccept,
                "client and server disagree on \(sample.debugDescription)"
            )
        }
    }

    // MARK: - Password validation

    func testPasswordBoundaries() {
        XCTAssertFalse(AuthService.isValidPassword("Passw1"), "6 chars")
        XCTAssertFalse(AuthService.isValidPassword("Passwo1"), "7 chars")
        XCTAssertTrue(AuthService.isValidPassword("Passwor1"), "8 chars is the floor")
        XCTAssertTrue(AuthService.isValidPassword("Password123456789012".prefix(20).description))
        XCTAssertFalse(
            AuthService.isValidPassword(String(repeating: "Aa1", count: 10)),
            "30 chars is above the 20-char ceiling"
        )
    }

    func testPasswordRequiresAllThreeCharacterClasses() {
        XCTAssertFalse(AuthService.isValidPassword("password1"), "no uppercase")
        XCTAssertFalse(AuthService.isValidPassword("PASSWORD1"), "no lowercase")
        XCTAssertFalse(AuthService.isValidPassword("PasswordX"), "no number")
        XCTAssertTrue(AuthService.isValidPassword("Password1"))
    }

    func testPasswordAllowsSymbolsAndUnicodeAlongsideTheRequiredClasses() {
        XCTAssertTrue(AuthService.isValidPassword("P@ssw0rd!"))
        XCTAssertTrue(AuthService.isValidPassword("Pass w0rd"), "internal space is fine")
        XCTAssertFalse(AuthService.isValidPassword("        "), "whitespace only")
    }

    // MARK: - Email validation

    func testEmailAcceptsRealisticAddresses() {
        let accepted = [
            "dreamer@example.com",
            "dreamer+tag@example.co.uk",
            "first.last@sub.domain.org",
            "d@e.io",
            "UPPER@EXAMPLE.COM",
            "  padded@example.com  ",           // trimmed before checking
            "abc123@privaterelay.appleid.com",  // Apple private relay
        ]
        for address in accepted {
            XCTAssertTrue(AuthService.isValidEmail(address), "expected \(address) to pass")
        }
    }

    func testEmailRejectsMalformedAddresses() {
        let rejected = [
            "", "dreamer", "dreamer@", "@example.com", "dreamer@example",
            "dreamer@@example.com", "dreamer @example.com", "dreamer@exa mple.com",
            "dreamer@example.c",                // TLD too short
            "dreamer@example.com\nBcc: x@y.com" // header injection
        ]
        for address in rejected {
            XCTAssertFalse(AuthService.isValidEmail(address), "expected \(address.debugDescription) to fail")
        }
    }

    // MARK: - Sign-up flow

    func testSignUpNormalisesTheHandleAndNames() async {
        let auth = AuthService(backend: MockAuthBackend())

        await auth.signUp(
            email: "  Dreamer@Example.com  ",
            password: "Password1",
            username: "  MoonWalker  ",
            firstName: "  Ada  ",
            lastName: "  Lovelace  "
        )

        XCTAssertEqual(auth.username, "moonwalker", "handle is trimmed and lowercased")
        XCTAssertEqual(auth.firstName, "Ada")
        XCTAssertEqual(auth.lastName, "Lovelace")
        XCTAssertTrue(auth.isSignedIn)
    }

    func testSignUpRejectsATakenUsernameWithoutSigningIn() async {
        UserDefaults.standard.set(["moonwalker"], forKey: "mockTakenUsernames")
        let auth = AuthService(backend: MockAuthBackend())

        await auth.signUp(
            email: "dreamer@example.com", password: "Password1",
            username: "MoonWalker", firstName: "Ada", lastName: "Lovelace"
        )

        XCTAssertFalse(auth.isSignedIn)
        XCTAssertNotNil(auth.errorMessage)
        XCTAssertTrue(auth.errorMessage?.contains("taken") ?? false)
    }

    func testSignUpRequiresBothNameParts() async {
        for (first, last) in [("", "Lovelace"), ("Ada", ""), ("   ", "Lovelace")] {
            let auth = AuthService(backend: MockAuthBackend())
            await auth.signUp(
                email: "dreamer@example.com", password: "Password1",
                username: "moonwalker", firstName: first, lastName: last
            )
            XCTAssertFalse(auth.isSignedIn, "\(first.debugDescription)/\(last.debugDescription) should not sign in")
            XCTAssertNotNil(auth.errorMessage)
        }
    }

    func testSignUpRejectsInvalidInputBeforeTouchingTheBackend() async {
        let backend = StubBackend()
        backend.signUpResult = .failure(AuthError.message("backend should not have been called"))

        let cases: [(String, String, String)] = [
            ("dreamer@example.com", "Password1", "ab"),          // handle too short
            ("dreamer@example.com", "weak", "moonwalker"),       // password policy
            ("not-an-email", "Password1", "moonwalker"),         // email shape
        ]
        for (email, password, username) in cases {
            let auth = AuthService(backend: backend)
            await auth.signUp(
                email: email, password: password, username: username,
                firstName: "Ada", lastName: "Lovelace"
            )
            XCTAssertFalse(auth.isSignedIn)
            XCTAssertNotNil(auth.errorMessage)
        }
        XCTAssertEqual(backend.signUpCallCount, 0, "invalid input must never reach the network")
    }

    func testSignUpAwaitingConfirmationDoesNotSignIn() async {
        let backend = StubBackend()
        backend.signUpResult = .success(
            SignUpOutcome(email: "dreamer@example.com",
                          needsEmailConfirmation: true,
                          isExistingUnconfirmedAccount: false)
        )
        let auth = AuthService(backend: backend)

        await auth.signUp(
            email: "dreamer@example.com", password: "Password1",
            username: "moonwalker", firstName: "Ada", lastName: "Lovelace"
        )

        XCTAssertFalse(auth.isSignedIn, "the session only exists after the link is tapped")
        XCTAssertEqual(auth.pendingConfirmationEmail, "dreamer@example.com")
        XCTAssertNil(auth.errorMessage)
    }

    /// Supabase silently keeps the original account and ignores the newly chosen
    /// username/password. The user has to be told, or they're locked out later.
    func testResignUpOverAnUnconfirmedAccountWarnsTheCredentialsDidNotChange() async {
        let backend = StubBackend()
        backend.signUpResult = .success(
            SignUpOutcome(email: "dreamer@example.com",
                          needsEmailConfirmation: true,
                          isExistingUnconfirmedAccount: true)
        )
        let auth = AuthService(backend: backend)

        await auth.signUp(
            email: "dreamer@example.com", password: "Password1",
            username: "moonwalker", firstName: "Ada", lastName: "Lovelace"
        )

        XCTAssertEqual(auth.pendingConfirmationEmail, "dreamer@example.com")
        XCTAssertNotNil(auth.errorMessage, "the user must be told their new details were ignored")
    }

    func testSignUpSurfacesABackendFailureAndStaysSignedOut() async {
        let backend = StubBackend()
        backend.signUpResult = .failure(AuthError.message("Network is unreachable."))
        let auth = AuthService(backend: backend)

        await auth.signUp(
            email: "dreamer@example.com", password: "Password1",
            username: "moonwalker", firstName: "Ada", lastName: "Lovelace"
        )

        XCTAssertFalse(auth.isSignedIn)
        XCTAssertEqual(auth.errorMessage, "Network is unreachable.")
    }

    // MARK: - Sign in with Apple

    func testAppleRequestUsesAFreshHashedNonceEachTime() {
        let auth = AuthService(backend: MockAuthBackend())

        let first = ASAuthorizationAppleIDProvider().createRequest()
        auth.prepareAppleRequest(first)
        let second = ASAuthorizationAppleIDProvider().createRequest()
        auth.prepareAppleRequest(second)

        XCTAssertNotNil(first.nonce)
        XCTAssertNotEqual(first.nonce, second.nonce, "a nonce must never be reused")
        // Apple receives the SHA-256 of the raw nonce: 64 lowercase hex chars.
        XCTAssertEqual(first.nonce?.count, 64)
        XCTAssertTrue(first.nonce?.allSatisfy { $0.isHexDigit && !$0.isUppercase } ?? false)
        XCTAssertEqual(first.requestedScopes.map(Set.init), Set([.email, .fullName]))
    }

    func testAppleCancellationIsNotAnError() async {
        let auth = AuthService(backend: MockAuthBackend())
        let cancelled = ASAuthorizationError(.canceled)

        await auth.completeAppleSignIn(.failure(cancelled))

        XCTAssertNil(auth.errorMessage, "backing out of the sheet is not a failure")
        XCTAssertFalse(auth.isSignedIn)
    }

    func testAppleFailureSurfacesAnError() async {
        let auth = AuthService(backend: MockAuthBackend())
        let failed = ASAuthorizationError(.failed)

        await auth.completeAppleSignIn(.failure(failed))

        XCTAssertNotNil(auth.errorMessage)
        XCTAssertFalse(auth.isSignedIn)
    }

    /// A first Apple sign-in has no profile on the server, so the user must land
    /// on the username-setup screen rather than a half-configured signed-in state.
    func testNewAppleUserNeedsProfileSetup() async {
        let backend = StubBackend()
        backend.profile = .absent
        let auth = AuthService(backend: backend)

        await auth.finishAppleSignIn(
            idToken: "stub.id.token", nonce: "raw-nonce",
            email: "abc@privaterelay.appleid.com",
            givenName: "Ada", familyName: "Lovelace"
        )

        XCTAssertTrue(auth.isSignedIn)
        XCTAssertTrue(auth.needsProfileSetup)
        XCTAssertEqual(auth.provider, .apple)
        XCTAssertFalse(auth.canChangePassword, "an Apple account has no password to change")
        XCTAssertEqual(auth.firstName, "Ada", "the one-and-only name Apple sends is kept")
        XCTAssertEqual(auth.lastName, "Lovelace")
    }

    /// Guideline 5.1.1(v): the grant has to be revocable at deletion time, and the
    /// authorization code is the only way to get a revocable token. It is
    /// single-use and short-lived, so if sign-in doesn't forward it, nothing can.
    func testAppleSignInForwardsTheAuthorizationCodeForLaterRevocation() async {
        let backend = StubBackend()
        backend.profile = .absent
        let auth = AuthService(backend: backend)

        await auth.finishAppleSignIn(
            idToken: "stub.id.token", nonce: "raw-nonce",
            email: "dreamer@icloud.com", givenName: nil, familyName: nil,
            authorizationCode: "apple-auth-code"
        )

        XCTAssertEqual(backend.linkedAuthorizationCodes, ["apple-auth-code"])
    }

    /// If the sign-in itself failed there is no session to authenticate the link
    /// call with, so it must not be attempted.
    func testNoAuthorizationCodeIsSentWhenSignInDidNotSucceed() async {
        let backend = StubBackend()
        backend.profile = .unreachable   // forces `perform` to undo the session
        let auth = AuthService(backend: backend)

        await auth.finishAppleSignIn(
            idToken: "stub.id.token", nonce: "raw-nonce",
            email: "dreamer@icloud.com", givenName: nil, familyName: nil,
            authorizationCode: "apple-auth-code"
        )

        XCTAssertFalse(auth.isSignedIn)
        XCTAssertTrue(backend.linkedAuthorizationCodes.isEmpty)
    }

    /// Apple sends the display name on the *first* authorization only. A returning
    /// user gets nil, which must not wipe the name already on the account.
    func testReturningAppleUserKeepsTheirExistingProfile() async {
        let backend = StubBackend()
        backend.profile = .found(
            ProfileInfo(username: "moonwalker", firstName: "Ada",
                        lastName: "Lovelace", bio: "", usernameChangedAt: nil)
        )
        let auth = AuthService(backend: backend)

        await auth.finishAppleSignIn(
            idToken: "stub.id.token", nonce: "raw-nonce",
            email: nil, givenName: nil, familyName: nil
        )

        XCTAssertTrue(auth.isSignedIn)
        XCTAssertFalse(auth.needsProfileSetup, "a returning user must not be asked to set up again")
        XCTAssertEqual(auth.username, "moonwalker")
        XCTAssertEqual(auth.firstName, "Ada")
    }

    /// Offline on a fresh device we cannot tell a returning user from a new one.
    /// Guessing "new" would drop them into setup and let them take a second handle.
    func testUnreachableProfileOnSignInUndoesTheSessionInsteadOfGuessing() async {
        let backend = StubBackend()
        backend.profile = .unreachable
        let auth = AuthService(backend: backend)

        await auth.finishAppleSignIn(
            idToken: "stub.id.token", nonce: "raw-nonce",
            email: "dreamer@icloud.com", givenName: nil, familyName: nil
        )

        XCTAssertFalse(auth.isSignedIn, "must not fall through to profile setup")
        XCTAssertFalse(auth.needsProfileSetup)
        XCTAssertNotNil(auth.errorMessage)
    }

    // MARK: - Content filter gate

    /// What the filter blocks is `ContentFilterTests`' job. This checks the
    /// narrower thing sign-up owns: that the gate is actually consulted for the
    /// handle *and* both name parts, not just the handle.
    func testContentGateCoversTheHandleAndBothNameParts() {
        let dirty = "sh1t_lord"
        XCTAssertTrue(ContentFilter.checkUsername(dirty).isBlocked, "precondition")

        XCTAssertNil(AuthService.contentRejection(
            username: "moonwalker", firstName: "Ada", lastName: "Lovelace"))
        XCTAssertNotNil(AuthService.contentRejection(
            username: dirty, firstName: "Ada", lastName: "Lovelace"))
        XCTAssertNotNil(AuthService.contentRejection(
            username: "moonwalker", firstName: dirty, lastName: "Lovelace"))
        XCTAssertNotNil(AuthService.contentRejection(
            username: "moonwalker", firstName: "Ada", lastName: dirty))
    }

    func testDirtyHandleNeverReachesTheBackend() async {
        let backend = StubBackend()
        let auth = AuthService(backend: backend)

        await auth.signUp(
            email: "dreamer@example.com", password: "Password1",
            username: "sh1t_lord", firstName: "Ada", lastName: "Lovelace"
        )

        XCTAssertFalse(auth.isSignedIn)
        XCTAssertNotNil(auth.errorMessage)
        XCTAssertEqual(backend.signUpCallCount, 0)
    }
}

// MARK: - Test double

/// Forwards to `MockAuthBackend` except where a test needs to pin the outcome.
/// Only the account-creation surface is steerable; everything else is delegated.
private final class StubBackend: AuthBackend, @unchecked Sendable {
    private let inner = MockAuthBackend()

    var signUpResult: Result<SignUpOutcome, Error>?
    var profile: ProfileFetch = .absent
    private(set) var signUpCallCount = 0
    private(set) var linkedAuthorizationCodes: [String] = []

    func signUp(email: String, password: String, username: String,
                firstName: String, lastName: String) async throws -> SignUpOutcome {
        signUpCallCount += 1
        switch signUpResult {
        case .success(let outcome): return outcome
        case .failure(let error): throw error
        case nil:
            return try await inner.signUp(email: email, password: password,
                                          username: username, firstName: firstName,
                                          lastName: lastName)
        }
    }

    func fetchProfile() async -> ProfileFetch { profile }

    // Straight delegation below.
    func currentEmail() async -> String? { await inner.currentEmail() }
    func currentProvider() async -> AuthProvider? { await inner.currentProvider() }
    func isUsernameAvailable(_ username: String) async throws -> Bool {
        try await inner.isUsernameAvailable(username)
    }
    func resendConfirmationEmail(_ email: String) async throws {
        try await inner.resendConfirmationEmail(email)
    }
    func handleEmailConfirmLink(_ url: URL) async throws { try await inner.handleEmailConfirmLink(url) }
    func signIn(email: String, password: String) async throws -> String {
        try await inner.signIn(email: email, password: password)
    }
    func signInWithApple(idToken: String, nonce: String, email: String?) async throws -> String {
        try await inner.signInWithApple(idToken: idToken, nonce: nonce, email: email)
    }
    func linkAppleAccount(authorizationCode: String) async {
        linkedAuthorizationCodes.append(authorizationCode)
    }
    func createProfile(username: String, firstName: String, lastName: String) async throws {
        try await inner.createProfile(username: username, firstName: firstName, lastName: lastName)
    }
    func updateBio(_ bio: String) async throws { try await inner.updateBio(bio) }
    func updateAvatar(_ data: Data?) async throws { try await inner.updateAvatar(data) }
    func fetchAvatar() async -> Data? { await inner.fetchAvatar() }
    func fetchBan() async -> BanInfo? { await inner.fetchBan() }
    func fetchAvatars(usernames: [String]) async -> [String: Data] {
        await inner.fetchAvatars(usernames: usernames)
    }
    func followCounts(for username: String) async -> FollowCounts {
        await inner.followCounts(for: username)
    }
    func followers(of username: String) async -> [FollowProfile] { await inner.followers(of: username) }
    func following(of username: String) async -> [FollowProfile] { await inner.following(of: username) }
    func searchProfiles(query: String, limit: Int) async -> [FollowProfile] {
        await inner.searchProfiles(query: query, limit: limit)
    }
    func blockUser(username: String) async throws { try await inner.blockUser(username: username) }
    func unblockUser(username: String) async throws { try await inner.unblockUser(username: username) }
    func blockedAccounts() async -> [FollowProfile] { await inner.blockedAccounts() }
    func fetchLucidProgress() async -> [String]? { await inner.fetchLucidProgress() }
    func updateLucidProgress(_ lessons: [String]) async throws {
        try await inner.updateLucidProgress(lessons)
    }
    func fetchProgressState() async -> ProgressState? { await inner.fetchProgressState() }
    func updateProgressState(_ state: ProgressState) async throws {
        try await inner.updateProgressState(state)
    }
    func updateUsername(_ username: String) async throws { try await inner.updateUsername(username) }
    func sendPasswordReset(email: String) async throws { try await inner.sendPasswordReset(email: email) }
    func changePassword(currentPassword: String, newPassword: String) async throws {
        try await inner.changePassword(currentPassword: currentPassword, newPassword: newPassword)
    }
    func handlePasswordResetLink(_ url: URL) async throws { try await inner.handlePasswordResetLink(url) }
    func updatePassword(_ newPassword: String) async throws { try await inner.updatePassword(newPassword) }
    func signOut() async throws { try await inner.signOut() }
    func deleteAccount() async throws { try await inner.deleteAccount() }
}
