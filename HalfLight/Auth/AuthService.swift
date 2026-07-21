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
// Imported by name so the SDK's `AuthError` can be referenced as
// `Auth.AuthError` (this file declares its own `AuthError`, which shadows it).
import Auth
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

/// A dreamer in a follower/following list — enough to render a row and open their
/// public profile. `photo` is their decoded avatar, if they've set one.
struct FollowProfile: Identifiable, Hashable, Sendable {
    let username: String
    let name: String
    let photo: Data?
    var id: String { username.lowercased() }
}

/// The size of a dreamer's social graph, shown on profile headers.
struct FollowCounts: Sendable, Equatable {
    var followers: Int
    var following: Int
    static let zero = FollowCounts(followers: 0, following: 0)
}

/// The result of creating an account: the resolved email and whether the user
/// must confirm it (via the emailed link) before a session exists.
struct SignUpOutcome: Sendable {
    let email: String
    let needsEmailConfirmation: Bool
    /// True when this email already had a never-confirmed account: Supabase
    /// re-sends that account's confirmation link and silently ignores the newly
    /// chosen username and password, so the app must tell the user the original
    /// credentials still apply.
    let isExistingUnconfirmedAccount: Bool
}

/// The outcome of fetching the signed-in user's profile. Distinguishes a brand
/// new account that has no profile yet (`absent` → show the setup screen) from a
/// transient failure such as being offline (`unreachable` → don't mistake a
/// returning user for a new one).
enum ProfileFetch: Sendable {
    case found(ProfileInfo)
    case absent
    case unreachable
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
    ) async throws -> SignUpOutcome
    /// Send a fresh sign-up confirmation email (the previous link may have
    /// expired, or the first email never arrived).
    func resendConfirmationEmail(_ email: String) async throws
    /// Exchange a tapped sign-up confirmation deep link for the account's first
    /// session, completing the sign-up.
    func handleEmailConfirmLink(_ url: URL) async throws
    func signIn(email: String, password: String) async throws -> String
    func signInWithApple(idToken: String, nonce: String, email: String?) async throws -> String
    /// Create the profile row for the currently signed-in user (used to finish
    /// onboarding accounts that didn't pick a username at sign-up, e.g. Apple).
    func createProfile(username: String, firstName: String, lastName: String) async throws
    /// The current user's existing profile. Reports `absent` when there's no
    /// profile yet and `unreachable` when the server couldn't be reached, so a
    /// returning user offline isn't treated as a new sign-up.
    func fetchProfile() async -> ProfileFetch
    /// Update the current user's bio (free-text; may be empty to clear it).
    func updateBio(_ bio: String) async throws
    /// Store the current user's profile photo (cropped JPEG), or clear it with
    /// `nil`, so it syncs across their devices.
    func updateAvatar(_ data: Data?) async throws
    /// The current user's profile photo, if one has been uploaded.
    func fetchAvatar() async -> Data?
    /// Other dreamers' profile photos, keyed by lowercased username. Absent for
    /// anyone who hasn't set a photo. Powers avatars on social surfaces (the feed
    /// and comments) where only the author's @handle is known.
    func fetchAvatars(usernames: [String]) async -> [String: Data]
    /// How many dreamers follow `username`, and how many it follows. Zeroed when
    /// the server can't be reached — a count is informational, never load-bearing.
    func followCounts(for username: String) async -> FollowCounts
    /// The dreamers who follow `username` (newest-agnostic, ordered by handle).
    func followers(of username: String) async -> [FollowProfile]
    /// The dreamers `username` follows.
    func following(of username: String) async -> [FollowProfile]
    /// Dreamers whose @handle or display name matches `query`, for the feed's
    /// account search. Best-effort — empty when the server can't be reached.
    func searchProfiles(query: String, limit: Int) async -> [FollowProfile]
    /// The completed Lucid Path lesson IDs stored on the account. `nil` when the
    /// server couldn't be reached, so a failed fetch never clobbers local progress.
    func fetchLucidProgress() async -> [String]?
    /// Store the completed Lucid Path lesson IDs on the account.
    func updateLucidProgress(_ lessons: [String]) async throws
    /// The account's synced progress blob (skipped/credit days, quest XP, claimed
    /// quests, quest seed). `nil` when the server couldn't be reached, so a failed
    /// fetch never clobbers local progress.
    func fetchProgressState() async -> ProgressState?
    /// Store the account's progress blob.
    func updateProgressState(_ state: ProgressState) async throws
    /// Change the current user's username. Throws if it's taken or the server's
    /// 30-day cooldown rejects it.
    func updateUsername(_ username: String) async throws
    func sendPasswordReset(email: String) async throws
    func changePassword(currentPassword: String, newPassword: String) async throws
    /// Exchange a tapped password-reset deep link for a (recovery) session, so the
    /// user can set a new password without knowing the old one.
    func handlePasswordResetLink(_ url: URL) async throws
    /// Set a new password for the user authenticated by the current session
    /// (used right after `handlePasswordResetLink`). No current password needed.
    func updatePassword(_ newPassword: String) async throws
    func signOut() async throws
    /// Permanently delete the current user's account and all server-side data.
    func deleteAccount() async throws
}

enum AuthError: LocalizedError {
    case message(String)
    /// The account exists but its email hasn't been confirmed yet — the app
    /// shows the "confirm your email" screen (with resend) instead of an error.
    case emailNotConfirmed
    var errorDescription: String? {
        switch self {
        case .message(let text): text
        case .emailNotConfirmed: "You haven't confirmed your email yet. Check your inbox for the confirmation link."
        }
    }
}

// MARK: - Observable service

@MainActor
@Observable
final class AuthService {
    enum Status: Equatable { case unknown, signedOut, signedIn }

    /// How the dreamer most recently reached the signed-in state. Drives whether
    /// on-device guest dreams are adopted automatically (a brand-new account, via
    /// `signedUp`) or the dreamer is asked first (logging into an existing account,
    /// via `signedIn`). `nil` for a launch session-restore, which adopts silently.
    enum AuthEntry: Equatable { case signedUp, signedIn }
    private(set) var lastEntry: AuthEntry?

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

    /// Live availability of the username being typed on the sign-up form.
    enum UsernameStatus: Equatable { case idle, checking, available, taken, invalid }
    private(set) var usernameStatus: UsernameStatus = .idle
    /// The in-flight debounced availability check, cancelled when the field changes.
    private var usernameCheckTask: Task<Void, Never>?

    /// Set after a sign-up that requires email confirmation (and when signing
    /// in with a still-unconfirmed account): the address the confirmation link
    /// was sent to. Drives the "confirm your email" screen; cleared once the
    /// link is redeemed or the user backs out to sign-in.
    private(set) var pendingConfirmationEmail: String?
    /// Surfaced (as an alert) when a tapped confirmation link couldn't be
    /// redeemed (expired, already used, or opened on a different device).
    var emailConfirmError: String?

    /// Set once a password-reset deep link has been exchanged for a recovery
    /// session; drives the modal "set a new password" screen.
    var isPresentingPasswordReset = false
    /// Surfaced (as an alert) when a tapped reset link couldn't be redeemed
    /// (expired, already used, or opened on a different device).
    var passwordResetError: String?

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
        let defaults = UserDefaults.standard
        username = defaults.string(forKey: "userUsername")
        firstName = defaults.string(forKey: "userFirstName")
        lastName = defaults.string(forKey: "userLastName")
        bio = defaults.string(forKey: "userBio")
        usernameChangedAt = defaults.object(forKey: "userUsernameChangedAt") as? Date

        guard email != nil else {
            status = .signedOut
            return
        }
        // A reinstall can restore the keychain session while UserDefaults (the
        // cached username) is gone. With no cached handle, pull the profile from
        // the server *before* exposing the signed-in state, so an existing account
        // isn't shown the setup gate. With a cached handle, show the app right away
        // and just refresh in the background.
        let hasCachedHandle = !(username?.isEmpty ?? true)
        if !hasCachedHandle {
            let outcome = await hydrateProfileIfNeeded()
            // Offline with no cached handle (e.g. reinstall restored the session but
            // cleared UserDefaults): we can't identify the account, so stay signed
            // out rather than show the setup gate. The keychain session survives, so
            // a later online launch restores them normally.
            if case .unreachable = outcome, (username?.isEmpty ?? true) {
                self.email = nil
                self.provider = .unknown
                status = .signedOut
                return
            }
        }
        status = .signedIn
        if hasCachedHandle {
            await hydrateProfileIfNeeded()
        }
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

    /// Other dreamers' profile photos for social surfaces, keyed by lowercased
    /// username. Best-effort: anyone missing (no photo, or unreachable) is simply
    /// absent and the caller falls back to initials.
    func avatars(forUsernames usernames: [String]) async -> [String: Data] {
        await backend.fetchAvatars(usernames: usernames)
    }

    // MARK: - Social graph (followers / following)

    /// Follower and following counts for any dreamer's profile. Best-effort —
    /// `.zero` when the server can't be reached.
    func followCounts(for username: String) async -> FollowCounts {
        await backend.followCounts(for: username)
    }

    /// The dreamers who follow `username`.
    func followers(of username: String) async -> [FollowProfile] {
        await backend.followers(of: username)
    }

    /// The dreamers `username` follows.
    func following(of username: String) async -> [FollowProfile] {
        await backend.following(of: username)
    }

    /// Search dreamers by @handle or display name for the feed's account search.
    /// Best-effort — a blank query (or an unreachable server) returns no matches.
    func searchProfiles(_ query: String, limit: Int = 20) async -> [FollowProfile] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return await backend.searchProfiles(query: trimmed, limit: limit)
    }

    // MARK: - Lucid Path progress (tied to the account, like dreams)

    /// Keep the account and the device in step on Lucid Path progress. Completion
    /// only ever grows, so this *unions* the two sets — the device picks up any
    /// lessons finished on another device, and the account picks up any finished
    /// here — and never loses progress. Used on sign-up, on a chosen merge, and on
    /// every launch/sign-in where local progress is kept. A failed fetch is left
    /// untouched (so we never overwrite the account with a stale local set).
    func syncLucidProgress() async {
        guard isSignedIn else { return }
        guard let remoteArray = await backend.fetchLucidProgress() else { return }
        let local = LucidProgress.completedIDs()
        let remote = Set(remoteArray)
        let union = local.union(remote)
        if union != local { LucidProgress.replaceAll(union) }
        if union != remote { try? await backend.updateLucidProgress(Array(union)) }
    }

    /// Drop the device's Lucid Path progress (declined the merge on sign-in), then
    /// pull the account's so the device reflects that account — mirroring how
    /// declining to merge dreams discards the local ones.
    func discardLocalLucidProgress() async {
        LucidProgress.clear()
        guard let remoteArray = await backend.fetchLucidProgress() else { return }
        LucidProgress.replaceAll(remoteArray)
    }

    /// Wipe the device's Lucid Path progress on sign-out — it lives on the account
    /// and rehydrates on the next sign-in, so the signed-out app shows zero.
    func clearLocalLucidProgress() {
        LucidProgress.clear()
    }

    // MARK: - Progress state sync (streak days, quest XP, quest seed)

    /// Keep the account and device in step on the progress blob — the "can't
    /// remember"/credit day logs, banked quest XP, claimed quests and quest seed.
    /// Merges (never loses) local and remote, applies the result locally, and
    /// pushes it back. A failed fetch is left untouched so a stale local set never
    /// clobbers the account. Mirrors `syncLucidProgress`; call it from the same
    /// places. Returns whether the local stores changed, so a caller holding a
    /// cache (e.g. `DreamStore`) knows to refresh.
    @discardableResult
    func syncProgressState() async -> Bool {
        guard isSignedIn else { return false }
        guard let remote = await backend.fetchProgressState() else { return false }
        let local = ProgressState.local()
        let merged = local.merged(with: remote)
        let changedLocally = merged != local
        if changedLocally { merged.applyLocally() }
        if merged != remote { try? await backend.updateProgressState(merged) }
        return changedLocally
    }

    /// Drop the device's local progress (declined the merge on sign-in), then pull
    /// the account's — mirroring how declining to merge dreams discards the local
    /// ones. Returns whether local stores changed so the caller can refresh caches.
    @discardableResult
    func discardLocalProgressState() async -> Bool {
        QuestRewards.reset()
        DayLog.skipped.clear()
        DayLog.journalCredit.clear()
        guard let remote = await backend.fetchProgressState() else { return true }
        remote.applyLocally()
        return true
    }

    /// Refresh the cached profile from the account whenever signed in: the server
    /// is the source of truth for a signed-in dreamer, so this also makes the
    /// account's first name win over any locally-set name (the greeting reads
    /// `userName`). Runs on every launch / sign-in. Returns the fetch outcome so
    /// callers can tell a genuinely new account apart from an offline failure; a
    /// failure (`unreachable`) leaves the cached values in place.
    @discardableResult
    private func hydrateProfileIfNeeded() async -> ProfileFetch {
        // Gate on a session (email set), not on `status`, so this can run *before*
        // we flip to `.signedIn` during `perform` — letting an existing account's
        // username load before the profile-setup gate is ever evaluated.
        guard email != nil else { return .unreachable }
        let outcome = await backend.fetchProfile()
        guard case .found(let remote) = outcome else { return outcome }
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
        return outcome
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
            // The profile row now exists (it didn't at sign-in for a new Apple
            // account), so push up any Lucid Path progress earned as a guest.
            await syncLucidProgress()
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
        // Trim the address too: validation trims before checking, so an email
        // with a stray space (e.g. from autocorrect) would pass the form but be
        // rejected by the server if sent raw.
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !first.isEmpty, !last.isEmpty else {
            errorMessage = "Please enter your first and last name."
            return
        }
        guard Self.isValidUsername(handle) else {
            errorMessage = "Usernames must be 3–20 characters using letters, numbers, or underscores."
            return
        }
        guard Self.isValidPassword(password) else {
            errorMessage = "Your password must be 8–20 characters and include an uppercase letter, a lowercase letter, and a number."
            return
        }
        guard Self.isValidEmail(address) else {
            errorMessage = "Please enter a valid email address."
            return
        }

        do {
            guard try await backend.isUsernameAvailable(handle) else {
                errorMessage = "“\(handle)” is taken. Try another username."
                return
            }
            let outcome = try await backend.signUp(
                email: address,
                password: password,
                username: handle,
                firstName: first,
                lastName: last
            )
            if outcome.needsEmailConfirmation {
                // The account exists but can't be used until the emailed link is
                // tapped — park on the "confirm your email" screen. The signed-in
                // state (and the profile hydrate) happens when the link comes
                // back in via `handleEmailConfirmLink`.
                pendingConfirmationEmail = outcome.email
                if outcome.isExistingUnconfirmedAccount {
                    // Supabase kept the original account and ignored the details
                    // just entered — say so, or the user will try their new
                    // password later and be locked out, confused.
                    errorMessage = "This email already has an account that was never confirmed. We've re-sent its confirmation link — note that your original username and password still apply (you can reset the password if you've forgotten it)."
                }
                return
            }
            persistProfile(username: handle, firstName: first, lastName: last)
            self.email = outcome.email
            self.provider = .email
            // A brand-new account: any on-device guest dreams are adopted silently.
            lastEntry = .signedUp
            status = .signedIn
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Send a fresh confirmation email to the pending address (the first one
    /// may have expired or never arrived).
    func resendConfirmation() async {
        guard let email = pendingConfirmationEmail else { return }
        isWorking = true
        errorMessage = nil
        infoMessage = nil
        defer { isWorking = false }
        do {
            try await backend.resendConfirmationEmail(email)
            infoMessage = "We've sent a new confirmation link to \(email)."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Leave the "confirm your email" screen and return to the sign-in form
    /// (e.g. to retry with a different address).
    func cancelPendingConfirmation() {
        pendingConfirmationEmail = nil
        errorMessage = nil
        infoMessage = nil
    }

    /// Whether a URL is our sign-up confirmation deep link (halflight://confirm-email).
    func isEmailConfirmLink(_ url: URL) -> Bool {
        url.scheme == "halflight" && url.host == "confirm-email"
    }

    /// Handle a tapped sign-up confirmation link: exchange it for the account's
    /// first session and bring the app to the signed-in state. The profile row
    /// already exists (created server-side at sign-up), so this hydrates it
    /// before exposing the signed-in state. Ignores unrelated URLs.
    func handleEmailConfirmLink(_ url: URL) async {
        guard isEmailConfirmLink(url) else { return }
        // A second tap on an already-redeemed link (or a tap while signed in)
        // would fail the exchange and pop a misleading "link expired" alert
        // over a perfectly good session — there's nothing to confirm, so bail.
        guard !isSignedIn else { return }
        isWorking = true
        errorMessage = nil
        emailConfirmError = nil
        defer { isWorking = false }
        do {
            try await backend.handleEmailConfirmLink(url)
            self.email = await backend.currentEmail()
            self.provider = .email
            pendingConfirmationEmail = nil
            // Pull the profile (username, name) before exposing the signed-in
            // state, mirroring `perform`, so the setup gate never misfires.
            let outcome = await hydrateProfileIfNeeded()
            if case .unreachable = outcome, (username?.isEmpty ?? true) {
                try? await backend.signOut()
                self.email = nil
                self.provider = .unknown
                emailConfirmError = "Couldn't reach the server. Check your connection and try again."
                return
            }
            // A confirmation link only ever completes a brand-new account, so
            // any on-device guest dreams are adopted silently.
            lastEntry = .signedUp
            status = .signedIn
            await hydrateAvatarIfNeeded()
        } catch {
            emailConfirmError = error.localizedDescription
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

    /// A basic well-formed email check: `local@domain.tld`. The sign-up form uses
    /// this live; it's also the backstop in `signUp`. (The server is the final
    /// authority on whether the address actually exists.)
    static func isValidEmail(_ email: String) -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = "^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }

    /// Passwords: 8–20 chars with at least one uppercase letter, one lowercase
    /// letter, and one number. The sign-up form enforces this live; this is the
    /// backstop so the policy can't be bypassed.
    static func isValidPassword(_ password: String) -> Bool {
        (8...20).contains(password.count)
            && password.contains(where: \.isUppercase)
            && password.contains(where: \.isLowercase)
            && password.contains(where: \.isNumber)
    }

    /// Debounced live availability check for the sign-up username field. Validates
    /// the format locally, then (after a short pause so we don't query every
    /// keystroke) asks the backend, publishing the outcome via `usernameStatus`.
    /// A network error leaves the status `idle` — sign-up's own check is the gate,
    /// so we never block the dreamer over a flaky lookup.
    func checkUsernameAvailability(_ raw: String) {
        usernameCheckTask?.cancel()
        let handle = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !handle.isEmpty else { usernameStatus = .idle; return }
        guard Self.isValidUsername(handle) else { usernameStatus = .invalid; return }

        usernameStatus = .checking
        usernameCheckTask = Task { [handle] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            do {
                let available = try await backend.isUsernameAvailable(handle)
                guard !Task.isCancelled else { return }
                usernameStatus = available ? .available : .taken
            } catch {
                guard !Task.isCancelled else { return }
                usernameStatus = .idle
            }
        }
    }

    /// Clear any pending check and reset the indicator (mode switch / field clear).
    func resetUsernameStatus() {
        usernameCheckTask?.cancel()
        usernameStatus = .idle
    }

    func signIn(email: String, password: String) async {
        // Trimmed for the same reason as sign-up: a stray space passes the
        // form's validation (which trims) but the server rejects it raw.
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        // `perform` hydrates the profile + photo before flipping to signed-in, so a
        // new device shows the right account immediately (no false setup prompt).
        let error = await perform(provider: .email) { try await self.backend.signIn(email: address, password: password) }
        // An account that never confirmed its email can't sign in — show the
        // "confirm your email" screen (with resend) alongside the explanation.
        if case .emailNotConfirmed = error as? AuthError {
            pendingConfirmationEmail = address
        }
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

    /// Whether a URL is our password-reset deep link (halflight://reset-password).
    func isPasswordResetLink(_ url: URL) -> Bool {
        url.scheme == "halflight" && url.host == "reset-password"
    }

    /// Handle a tapped password-reset link: redeem it for a recovery session and,
    /// on success, present the "set a new password" screen. Ignores unrelated URLs.
    func handlePasswordResetLink(_ url: URL) async {
        guard isPasswordResetLink(url) else { return }
        isWorking = true
        errorMessage = nil
        passwordResetError = nil
        defer { isWorking = false }
        do {
            try await backend.handlePasswordResetLink(url)
            isPresentingPasswordReset = true
        } catch {
            passwordResetError = error.localizedDescription
        }
    }

    /// Set the new password using the recovery session from the reset link, then
    /// bring the app to a signed-in state. Returns `true` on success.
    @discardableResult
    func completePasswordReset(newPassword: String) async -> Bool {
        isWorking = true
        errorMessage = nil
        infoMessage = nil
        defer { isWorking = false }
        do {
            try await backend.updatePassword(newPassword)
            // The recovery session is a full session now — sync profile/state.
            await restore()
            isPresentingPasswordReset = false
            infoMessage = "Your password has been updated."
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
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
        // Save this session's progress to the account *before* the session ends and
        // the sign-out wipe clears it locally. Otherwise quests claimed (or streak
        // days logged) during the session — which are only pushed on launch/sign-in
        // otherwise — wouldn't reach the account, and the next sign-in would pull a
        // stale state: changed quests, lost claims. Runs while still authenticated.
        await syncLucidProgress()
        await syncProgressState()
        do {
            try await backend.signOut()
            // Wipe the cached identity (name, @handle, bio, photo) so the signed-out
            // Profile tab falls back to the default "Dreamer" and the next account
            // doesn't inherit it — each rehydrates from the server on sign-in.
            clearPersistedProfile()
            email = nil
            provider = .unknown
            username = nil
            firstName = nil
            lastName = nil
            bio = nil
            usernameChangedAt = nil
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
            // `perform` pulls any existing profile + photo before flipping to
            // signed-in, so a returning Apple user isn't asked to set up again.
            await perform(provider: .apple) {
                try await self.backend.signInWithApple(idToken: idToken, nonce: nonce, email: appleEmail)
            }
            // Genuinely new account (no profile on the server): prefill the
            // username-setup screen with the name Apple just gave us (first sign-in
            // only — Apple won't send it again).
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

    /// Returns the thrown error (already surfaced via `errorMessage`) so callers
    /// can react to specific failures, e.g. an unconfirmed email on sign-in.
    @discardableResult
    private func perform(provider: AuthProvider, _ work: @escaping () async throws -> String) async -> Error? {
        isWorking = true
        errorMessage = nil
        infoMessage = nil
        defer { isWorking = false }
        do {
            let email = try await work()
            self.email = email
            self.provider = provider
            // Load the saved profile (username + name) *before* exposing the
            // signed-in state. Otherwise an existing account on a fresh device —
            // whose username lives only on the server — is momentarily seen as
            // having none, which wrongly pops the profile-setup screen.
            let outcome = await hydrateProfileIfNeeded()
            // Offline on a device with no cached handle: we can't tell whether this
            // account already has a profile, so don't guess. Undo the sign-in and
            // surface a clear error instead of dropping into the setup screen.
            if case .unreachable = outcome, (username?.isEmpty ?? true) {
                try? await backend.signOut()
                self.email = nil
                self.provider = .unknown
                errorMessage = "Couldn't reach the server. Check your connection and try again."
                return nil
            }
            // No username yet means this is a brand-new account (e.g. first Apple
            // sign-in) — adopt guest dreams silently. An existing account already
            // has a handle, so logging in prompts before merging device dreams.
            lastEntry = (username?.isEmpty ?? true) ? .signedUp : .signedIn
            status = .signedIn
            await hydrateAvatarIfNeeded()
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return error
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
    ) async throws -> SignUpOutcome {
        try validate(email: email, password: password)
        var taken = Set(UserDefaults.standard.stringArray(forKey: usernamesKey) ?? [])
        guard taken.insert(username.lowercased()).inserted else {
            throw AuthError.message("“\(username)” is taken. Try another username.")
        }
        UserDefaults.standard.set(Array(taken), forKey: usernamesKey)
        UserDefaults.standard.set(email, forKey: key)
        UserDefaults.standard.set(AuthProvider.email.rawValue, forKey: providerKey)
        // No email delivery in the mock — accounts are auto-confirmed.
        return SignUpOutcome(email: email, needsEmailConfirmation: false, isExistingUnconfirmedAccount: false)
    }

    func resendConfirmationEmail(_ email: String) async throws {
        // No-op in the mock — pretend the email was sent.
    }

    func handleEmailConfirmLink(_ url: URL) async throws {
        // No real backend — accept any halflight://confirm-email link.
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

    func fetchProfile() async -> ProfileFetch {
        // No real server in the mock — same-device username persists locally, so
        // there's never a remote profile to pull.
        .absent
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

    func fetchAvatars(usernames: [String]) async -> [String: Data] {
        // Single-device mock: only our own photo is known, keyed by our handle.
        guard let data = UserDefaults.standard.data(forKey: "mockAvatar"),
              let me = UserDefaults.standard.string(forKey: "userUsername")?.lowercased(),
              usernames.contains(where: { $0.lowercased() == me }) else { return [:] }
        return [me: data]
    }

    func followCounts(for username: String) async -> FollowCounts {
        // No multi-user backend in the mock — the social graph is empty.
        .zero
    }

    func followers(of username: String) async -> [FollowProfile] { [] }

    func following(of username: String) async -> [FollowProfile] { [] }

    func searchProfiles(query: String, limit: Int) async -> [FollowProfile] { [] }

    func fetchLucidProgress() async -> [String]? {
        // The mock is always "reachable", so report an empty set (not nil) when
        // nothing has been stored yet.
        UserDefaults.standard.stringArray(forKey: "mockLucidProgress") ?? []
    }

    func updateLucidProgress(_ lessons: [String]) async throws {
        UserDefaults.standard.set(lessons, forKey: "mockLucidProgress")
    }

    func fetchProgressState() async -> ProgressState? {
        // Always "reachable": decode the stored blob, or an empty state if none.
        guard let data = UserDefaults.standard.data(forKey: "mockProgressState"),
              let state = try? JSONDecoder().decode(ProgressState.self, from: data)
        else { return .empty }
        return state
    }

    func updateProgressState(_ state: ProgressState) async throws {
        UserDefaults.standard.set(try? JSONEncoder().encode(state), forKey: "mockProgressState")
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

    func handlePasswordResetLink(_ url: URL) async throws {
        // No real backend — accept any halflight://reset-password link.
    }

    func updatePassword(_ newPassword: String) async throws {
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
        // Decode a minimal row, not the full `ProfileRow`: the query only selects
        // `username`, so decoding into `ProfileRow` (which also needs id/first/last)
        // would throw whenever a row exists — i.e. exactly when the name is taken.
        struct UsernameRow: Decodable { let username: String }
        let rows: [UsernameRow] = try await client
            .from("profiles")
            .select("username")
            .eq("username", value: username)
            .limit(1)
            .execute()
            .value
        return rows.isEmpty
    }

    /// Map a failed `profiles` insert to a meaningful error. Only a genuine
    /// unique-constraint violation (Postgres 23505) means the username is taken;
    /// every other failure — a row-level-security rejection (e.g. no session
    /// because email confirmation is on), a network blip — is surfaced as-is so a
    /// real problem isn't hidden behind a misleading "username was just taken".
    private func profileInsertError(_ error: Error, username: String) -> AuthError {
        if let pg = error as? PostgrestError {
            if pg.code == "23505" {
                return .message("“\(username)” was just taken. Try another username.")
            }
            return .message(pg.message)
        }
        return .message(error.localizedDescription)
    }

    func signUp(
        email: String,
        password: String,
        username: String,
        firstName: String,
        lastName: String
    ) async throws -> SignUpOutcome {
        guard SupabaseConfig.isConfigured else { throw notConfigured }
        let response = try await client.auth.signUp(
            email: email,
            password: password,
            data: [
                "username": .string(username),
                "first_name": .string(firstName),
                "last_name": .string(lastName)
            ],
            // The confirmation email's link returns the user to the app, where
            // it's exchanged for the account's first session.
            redirectTo: SupabaseConfig.emailConfirmRedirect
        )
        // Supabase doesn't error on a duplicate email when confirmations are on
        // (it avoids leaking which emails exist); instead it returns a user with
        // an empty `identities` array. Treat that as "already registered".
        if let identities = response.user.identities, identities.isEmpty {
            throw AuthError.message("An account with this email already exists. Try resetting your password instead.")
        }
        // Re-signing up with a never-confirmed email is NOT a new account:
        // Supabase returns the original user (identities intact), re-sends its
        // confirmation link, and silently ignores the new username and password.
        // Detect it so the UI can say the original credentials still apply. A
        // fresh account's confirmation is sent within seconds of its creation;
        // a re-send lands much later (both are server clocks, so no skew). The
        // metadata check is a fallback for the same trap caught mid-signup.
        let isExistingUnconfirmed: Bool = {
            if let sent = response.user.confirmationSentAt,
               sent.timeIntervalSince(response.user.createdAt) > 60 { return true }
            if case let .string(existing)? = response.user.userMetadata["username"],
               existing.lowercased() != username.lowercased() { return true }
            return false
        }()
        // The profiles row is created server-side by the `on_auth_user_created`
        // trigger (from the metadata above): with email confirmation on there is
        // no session yet, so the client couldn't insert it under RLS anyway.
        // No session in the response means the user must confirm first.
        return SignUpOutcome(
            email: response.user.email ?? email,
            needsEmailConfirmation: response.session == nil,
            isExistingUnconfirmedAccount: isExistingUnconfirmed
        )
    }

    func resendConfirmationEmail(_ email: String) async throws {
        guard SupabaseConfig.isConfigured else { throw notConfigured }
        try await client.auth.resend(
            email: email,
            type: .signup,
            emailRedirectTo: SupabaseConfig.emailConfirmRedirect
        )
    }

    func handleEmailConfirmLink(_ url: URL) async throws {
        guard SupabaseConfig.isConfigured else { throw notConfigured }
        // PKCE flow, like the reset link: the link carries `?code=…`, exchanged
        // (with the verifier stored at sign-up on this device) for a session.
        do {
            try await client.auth.session(from: url)
        } catch {
            throw AuthError.message("This confirmation link has expired or was already used. Try signing in — if that fails, request a new link.")
        }
    }

    func signIn(email: String, password: String) async throws -> String {
        guard SupabaseConfig.isConfigured else { throw notConfigured }
        do {
            let session = try await client.auth.signIn(email: email, password: password)
            return session.user.email ?? email
        } catch let error as Auth.AuthError where error.errorCode == .emailNotConfirmed {
            // Surfaced as the "confirm your email" screen, not a raw error.
            throw AuthError.emailNotConfirmed
        }
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
            throw profileInsertError(error, username: username)
        }
    }

    func fetchProfile() async -> ProfileFetch {
        guard SupabaseConfig.isConfigured,
              (try? await client.auth.session) != nil else { return .unreachable }
        // `my_profile()` returns the caller's own row including their name, which
        // is private from everyone else — so the app can greet returning users by
        // their account first name on any device. A thrown error means we couldn't
        // reach the server (offline); an empty result means no profile row yet.
        do {
            let rows: [MyProfileRow] = try await client
                .rpc("my_profile")
                .execute()
                .value
            guard let row = rows.first else { return .absent }
            return .found(ProfileInfo(
                username: row.username,
                firstName: row.firstName ?? "",
                lastName: row.lastName ?? "",
                bio: row.bio ?? "",
                usernameChangedAt: row.usernameChangedAt.flatMap(Self.parseTimestamp)
            ))
        } catch {
            return .unreachable
        }
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

    func fetchAvatars(usernames: [String]) async -> [String: Data] {
        guard SupabaseConfig.isConfigured, !usernames.isEmpty else { return [:] }
        struct AvatarRow: Decodable { let username: String; let avatar: String? }
        // RLS exposes the avatar column to any signed-in user and SELECT spans all
        // rows, so a single `in` query pulls every author's photo at once.
        let rows: [AvatarRow]? = try? await client
            .from("profiles")
            .select("username, avatar")
            .in("username", values: usernames)
            .execute()
            .value
        guard let rows else { return [:] }
        var result: [String: Data] = [:]
        for row in rows {
            if let encoded = row.avatar, let data = Data(base64Encoded: encoded) {
                result[row.username.lowercased()] = data
            }
        }
        return result
    }

    func followCounts(for username: String) async -> FollowCounts {
        guard SupabaseConfig.isConfigured else { return .zero }
        struct CountRow: Decodable { let followers: Int; let following: Int }
        // The base `follows` table's RLS hides other users' rows, so the count of
        // who follows someone is only reachable through this SECURITY DEFINER RPC.
        let rows: [CountRow]? = try? await client
            .rpc("follow_counts", params: ["p_username": username])
            .execute()
            .value
        guard let row = rows?.first else { return .zero }
        return FollowCounts(followers: row.followers, following: row.following)
    }

    func followers(of username: String) async -> [FollowProfile] {
        await fetchFollowProfiles(rpc: "followers_of", username: username)
    }

    func following(of username: String) async -> [FollowProfile] {
        await fetchFollowProfiles(rpc: "following_of", username: username)
    }

    /// Shared decoder for the `followers_of` / `following_of` RPCs, which both
    /// return `(username, name, avatar)` rows for the requested @handle.
    private func fetchFollowProfiles(rpc: String, username: String) async -> [FollowProfile] {
        guard SupabaseConfig.isConfigured else { return [] }
        struct Row: Decodable { let username: String; let name: String; let avatar: String? }
        let rows: [Row]? = try? await client
            .rpc(rpc, params: ["p_username": username])
            .execute()
            .value
        guard let rows else { return [] }
        return rows.map { row in
            FollowProfile(
                username: row.username,
                name: row.name,
                photo: row.avatar.flatMap { Data(base64Encoded: $0) }
            )
        }
    }

    func searchProfiles(query: String, limit: Int) async -> [FollowProfile] {
        guard SupabaseConfig.isConfigured else { return [] }
        struct Params: Encodable { let p_query: String; let p_limit: Int }
        struct Row: Decodable { let username: String; let name: String; let avatar: String? }
        // Names aren't selectable on `profiles` directly (column grants expose only
        // username/avatar), so this goes through the SECURITY DEFINER RPC. `p_query`
        // is a bind parameter, so any `%`/`_` in the query just widens the ILIKE
        // rather than being an injection risk.
        let rows: [Row]? = try? await client
            .rpc("search_profiles", params: Params(p_query: query, p_limit: limit))
            .execute()
            .value
        guard let rows else { return [] }
        return rows.map { row in
            FollowProfile(
                username: row.username,
                name: row.name,
                photo: row.avatar.flatMap { Data(base64Encoded: $0) }
            )
        }
    }

    func fetchLucidProgress() async -> [String]? {
        guard SupabaseConfig.isConfigured,
              let userID = (try? await client.auth.session)?.user.id else { return nil }
        struct LucidRow: Decodable {
            let lucidCompletedLessons: [String]?
            enum CodingKeys: String, CodingKey { case lucidCompletedLessons = "lucid_completed_lessons" }
        }
        // A thrown error → `nil` (unreachable), so the caller won't overwrite the
        // account with a stale local set. A present-but-empty column → `[]`.
        guard let rows: [LucidRow] = try? await client
            .from("profiles")
            .select("lucid_completed_lessons")
            .eq("id", value: userID)
            .limit(1)
            .execute()
            .value
        else { return nil }
        return rows.first?.lucidCompletedLessons ?? []
    }

    func updateLucidProgress(_ lessons: [String]) async throws {
        guard SupabaseConfig.isConfigured else { throw notConfigured }
        guard let userID = (try? await client.auth.session)?.user.id else {
            throw AuthError.message("You need to be signed in to save your progress.")
        }
        struct LucidUpdate: Encodable {
            let lucidCompletedLessons: [String]
            enum CodingKeys: String, CodingKey { case lucidCompletedLessons = "lucid_completed_lessons" }
        }
        try await client
            .from("profiles")
            .update(LucidUpdate(lucidCompletedLessons: lessons))
            .eq("id", value: userID)
            .execute()
    }

    func fetchProgressState() async -> ProgressState? {
        guard SupabaseConfig.isConfigured,
              let userID = (try? await client.auth.session)?.user.id else { return nil }
        struct ProgressRow: Decodable {
            let progressState: ProgressState?
            enum CodingKeys: String, CodingKey { case progressState = "progress_state" }
        }
        // A thrown error → `nil` (unreachable), so the caller won't overwrite the
        // account with a stale local set. A present-but-null column → empty state.
        guard let rows: [ProgressRow] = try? await client
            .from("profiles")
            .select("progress_state")
            .eq("id", value: userID)
            .limit(1)
            .execute()
            .value
        else { return nil }
        return rows.first?.progressState ?? .empty
    }

    func updateProgressState(_ state: ProgressState) async throws {
        guard SupabaseConfig.isConfigured else { throw notConfigured }
        guard let userID = (try? await client.auth.session)?.user.id else {
            throw AuthError.message("You need to be signed in to save your progress.")
        }
        struct ProgressUpdate: Encodable {
            let progressState: ProgressState
            enum CodingKeys: String, CodingKey { case progressState = "progress_state" }
        }
        try await client
            .from("profiles")
            .update(ProgressUpdate(progressState: state))
            .eq("id", value: userID)
            .execute()
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

    func handlePasswordResetLink(_ url: URL) async throws {
        guard SupabaseConfig.isConfigured else { throw notConfigured }
        // PKCE flow: the link carries `?code=…`; this exchanges it (using the
        // verifier stored when the reset was requested on this device) for a
        // recovery session. Throws if the link is expired or already used.
        do {
            try await client.auth.session(from: url)
        } catch {
            throw AuthError.message("This reset link has expired or already been used. Request a new one.")
        }
    }

    func updatePassword(_ newPassword: String) async throws {
        guard SupabaseConfig.isConfigured else { throw notConfigured }
        guard (try? await client.auth.session) != nil else {
            throw AuthError.message("Your reset link is no longer valid. Request a new one.")
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
