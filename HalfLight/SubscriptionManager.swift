//
//  SubscriptionManager.swift
//  HalfLight
//
//  StoreKit 2 entitlement for "HalfLight Pro" — the subscription that unlocks the
//  AI features (analyze, auto-tag, auto-title). Mirrors the app's `@Observable`
//  pattern (see `DreamAnalyzer` / `AuthService`) so it injects via `.environment`.
//
//  Two auto-renewable products in one subscription group:
//    • monthly — $9.99 / month
//    • yearly  — $49.99 / year, with a 1-week free trial intro offer
//
//  The client gates the UI; the server is the source of truth for the bill. After
//  any entitlement change we POST the verified transaction to the
//  `sync-subscription` edge function so the AI functions can confirm the caller is
//  actually subscribed before spending on Claude.
//

import Foundation
import StoreKit
#if canImport(Supabase)
import Supabase
#endif
#if canImport(UIKit)
import UIKit
#endif

@MainActor
@Observable
final class SubscriptionManager {
    /// Product identifiers — must match App Store Connect (and `HalfLight.storekit`).
    enum ProductID {
        static let monthly = "LanternHours.HalfLight.pro.monthly"
        static let yearly = "LanternHours.HalfLight.pro.yearly"
        static var all: [String] { [monthly, yearly] }
    }

    /// The loaded monthly product, once `loadProducts()` succeeds.
    private(set) var monthly: Product?
    /// The loaded yearly product, once `loadProducts()` succeeds.
    private(set) var yearly: Product?

    /// True when the dreamer has an active (non-revoked, unexpired) entitlement.
    /// The single flag the rest of the app gates on.
    private(set) var isSubscribed = false

    /// True when the App Store returned neither product — the paywall shows a
    /// retry rather than invented prices.
    private(set) var productsUnavailable = false

    /// True when this Apple ID can still use the yearly plan's introductory
    /// offer. Someone who already had the trial must never be promised it again.
    private(set) var isEligibleForYearlyTrial = false

    /// True while a purchase or restore is in flight, to drive button spinners.
    private(set) var isPurchasing = false
    /// A user-facing message when a purchase fails; `nil` when there's no error.
    /// Already localized — display it verbatim.
    private(set) var errorMessage: String?
    /// Whether the last attempt to record the entitlement on the server
    /// succeeded. Drives the Restore result message in Settings.
    private(set) var lastSyncSucceeded = false

    /// How the last `restore()` ended, so Settings can report something true
    /// rather than inferring it from two booleans.
    enum RestoreOutcome {
        /// No restore has run yet this session.
        case none
        /// Restored and recorded on the server — Pro is fully live.
        case restored
        /// This Apple ID has no active HalfLight Pro subscription.
        case notFound
        /// The App Store has the subscription, but there's no account to attach
        /// it to; the AI features are server-gated, so they need to sign in.
        case needsSignIn
        /// Entitled, but the server wouldn't record it (offline, outage).
        case syncFailed
    }
    private(set) var lastRestoreOutcome: RestoreOutcome = .none

    /// The long-running task that observes out-of-band entitlement changes
    /// (renewals, Ask-to-Buy approvals, refunds, family-sharing, …).
    private var updatesListener: Task<Void, Never>?

    /// Start at launch: begin listening for transaction updates, load the products,
    /// and compute the current entitlement.
    func start() async {
        if updatesListener == nil {
            updatesListener = listenForTransactions()
        }
        await loadProducts()
        await refreshEntitlement()
    }

    /// Fetch the two products from the App Store (or local `.storekit` config).
    /// Prices shown to the dreamer come only from these, never from a hardcoded
    /// figure — a guessed "$9.99" is wrong in every storefront but the US.
    func loadProducts() async {
        do {
            let products = try await Product.products(for: ProductID.all)
            monthly = products.first { $0.id == ProductID.monthly }
            yearly = products.first { $0.id == ProductID.yearly }
        } catch {
            // Leave any previously loaded products in place; a failed refresh
            // shouldn't blank out a paywall that was already showing real prices.
        }
        productsUnavailable = monthly == nil && yearly == nil
        errorMessage = productsUnavailable
            ? localized("Couldn't load subscription options. Check your connection.")
            : nil
        await refreshTrialEligibility()
    }

    /// Ask the App Store whether the yearly plan's introductory offer is still
    /// available to this Apple ID. Anyone who has already used the trial (or held
    /// any subscription in the group) is ineligible, and showing them "1 week
    /// free" would be a promise the App Store won't honour at checkout.
    func refreshTrialEligibility() async {
        guard let subscription = yearly?.subscription,
              subscription.introductoryOffer != nil else {
            isEligibleForYearlyTrial = false
            return
        }
        isEligibleForYearlyTrial = await subscription.isEligibleForIntroOffer
    }

    /// The yearly plan's introductory offer, but only when this Apple ID can
    /// actually still use it. `nil` means sell the plan without trial copy.
    var yearlyTrialOffer: Product.SubscriptionOffer? {
        guard isEligibleForYearlyTrial else { return nil }
        return yearly?.subscription?.introductoryOffer
    }

    /// Clear a stale failure so a re-opened paywall doesn't greet the dreamer
    /// with the last session's error.
    func clearError() {
        errorMessage = nil
    }

    /// Buy a product. Returns true when the purchase completes and unlocks Pro.
    ///
    /// Refuses to charge a signed-out dreamer: everything Pro buys runs on the
    /// server behind their Supabase account, so a guest purchase would take the
    /// money and unlock nothing. The paywall sends them to sign in first; this
    /// guard makes that impossible to route around.
    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        errorMessage = nil

        guard let userID = await currentUserID() else {
            errorMessage = localized("Sign in first — HalfLight Pro unlocks the AI features on your account.")
            return false
        }

        isPurchasing = true
        defer { isPurchasing = false }

        do {
            // Tag the purchase with the signed-in user's id so Apple's server
            // notifications (which carry no Supabase JWT) can map renewals and
            // refunds back to this dreamer via `appAccountToken`.
            let result = try await product.purchase(options: [.appAccountToken(userID)])
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await refreshEntitlement()
                await syncToServer()
                await transaction.finish()
                await refreshTrialEligibility()
                return isSubscribed
            case .userCancelled:
                return false
            case .pending:
                // Ask-to-Buy / SCA: resolves later via the updates listener.
                errorMessage = localized("Your purchase is pending approval.")
                return false
            @unknown default:
                return false
            }
        } catch {
            errorMessage = localized("Purchase failed. Please try again.")
            return false
        }
    }

    /// Restore purchases — asks the App Store to re-sync, then recomputes.
    /// Records *why* it ended the way it did, since "no subscription found",
    /// "signed out" and "the server didn't take it" all need different advice.
    func restore() async {
        errorMessage = nil
        isPurchasing = true
        defer { isPurchasing = false }

        try? await AppStore.sync()
        await refreshEntitlement()
        await refreshTrialEligibility()

        guard isSubscribed else {
            lastRestoreOutcome = .notFound
            errorMessage = localized("No active subscription found to restore.")
            return
        }
        // Entitled on this Apple ID, but Pro's features are gated on the server
        // by account — without a session there's nothing to attach it to.
        guard await currentAccessToken() != nil else {
            lastRestoreOutcome = .needsSignIn
            errorMessage = localized("Sign in to finish restoring HalfLight Pro.")
            return
        }
        await syncToServer()
        lastRestoreOutcome = lastSyncSucceeded ? .restored : .syncFailed
    }

    /// Recompute on return to the foreground. A period can end, a cancellation
    /// can take effect, or a subscription can be started in Settings.app while
    /// we're away — and an expiry in particular doesn't always arrive as a
    /// transaction update, so the gates would otherwise read last session's
    /// answer. Also retries a sync that never landed.
    func refreshOnForeground() async {
        await refreshEntitlement()
        await refreshTrialEligibility()
        if isSubscribed && !lastSyncSucceeded { await syncToServer() }
    }

    /// Push the current entitlement to the server if the dreamer is subscribed.
    /// Called on sign-in so an entitled account whose server row is missing (a
    /// failed earlier sync, or a purchase made on another account) self-heals.
    func syncIfEntitled() async {
        await refreshEntitlement()
        if isSubscribed { await syncToServer() }
    }

    /// Open the system "Manage Subscriptions" sheet.
    func showManageSubscriptions() async {
        #if os(iOS)
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        else { return }
        try? await AppStore.showManageSubscriptions(in: scene)
        await refreshEntitlement()
        #endif
    }

    // MARK: - Entitlement

    /// Recompute `isSubscribed` from the current verified entitlements.
    func refreshEntitlement() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            guard ProductID.all.contains(transaction.productID) else { continue }
            if transaction.revocationDate == nil,
               !(transaction.expirationDate.map { $0 < Date() } ?? false) {
                active = true
            }
        }
        isSubscribed = active
    }

    /// Stream of transaction updates that happen outside an explicit purchase.
    private func listenForTransactions() -> Task<Void, Never> {
        Task(priority: .background) { [weak self] in
            for await update in Transaction.updates {
                // Nothing left to update — stop draining the stream.
                guard let self else { return }
                if let transaction = try? self.checkVerified(update) {
                    await self.refreshEntitlement()
                    await self.syncToServer()
                    await transaction.finish()
                    await self.refreshTrialEligibility()
                }
            }
        }
    }

    /// Unwrap a StoreKit `VerificationResult`, throwing if Apple couldn't verify it.
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }

    enum StoreError: Error { case failedVerification }

    // MARK: - Server sync

    /// Make sure the server knows about this device's entitlement, re-running a
    /// sync that hasn't succeeded yet. Returns true when the server should now see
    /// the dreamer as subscribed.
    ///
    /// The AI functions gate on the server's row, not on `isSubscribed`, so a
    /// dropped sync is exactly what makes someone who just paid look unsubscribed.
    /// Call this when a request comes back refused and retry it on `true`.
    @discardableResult
    func ensureServerEntitlement() async -> Bool {
        await refreshEntitlement()
        guard isSubscribed else { return false }
        if lastSyncSucceeded { return true }
        await syncToServer()
        return lastSyncSucceeded
    }

    /// POST the latest verified transaction's signed JWS to the `sync-subscription`
    /// edge function so the server records the entitlement. Retried a couple of
    /// times over a few seconds, since this is what stands between paying and using
    /// the AI features; the App Store Server Notifications webhook is the durable
    /// backstop for anything that still doesn't land.
    private func syncToServer() async {
        lastSyncSucceeded = false

        for (attempt, delay) in Self.syncAttemptDelays.enumerated() {
            if attempt > 0 { try? await Task.sleep(for: delay) }
            // Re-read both each time: the access token may have refreshed, and a
            // sign-in may have arrived between attempts.
            guard let jws = await latestTransactionJWS(),
                  let accessToken = await currentAccessToken() else { return }

            let status = await postSync(jws: jws, accessToken: accessToken)
            if let status, (200..<300).contains(status) {
                lastSyncSucceeded = true
                return
            }
            // A rejected purchase (400) or a bad route won't fix itself; only
            // network failures, expired tokens and server errors are worth another go.
            if let status, !Self.retriableSyncStatuses.contains(status) { return }
        }
    }

    /// Waits before each sync attempt — the first goes out immediately.
    private static let syncAttemptDelays: [Duration] = [.zero, .milliseconds(600), .seconds(3)]

    /// Sync failures worth retrying: an expired token, a timeout, rate limiting,
    /// or a server-side hiccup.
    private static let retriableSyncStatuses: Set<Int> = [401, 408, 429, 500, 502, 503, 504]

    /// One attempt at recording the entitlement. Returns the HTTP status, or `nil`
    /// when the request never reached the server.
    private func postSync(jws: String, accessToken: String) async -> Int? {
        let endpoint = SupabaseConfig.url
            .appendingPathComponent("functions/v1/sync-subscription")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONEncoder().encode(["jws": jws])

        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return nil }
        return (response as? HTTPURLResponse)?.statusCode
    }

    /// The signed JWS of the most recent verified Pro transaction, used by the
    /// server to verify the subscription against Apple's public keys.
    ///
    /// Picks the newest by purchase date rather than whichever the stream yields
    /// first: after a plan change the group can hold more than one entitlement,
    /// and sending the older one would record a stale expiry on the server.
    private func latestTransactionJWS() async -> String? {
        var newest: (date: Date, jws: String)?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  ProductID.all.contains(transaction.productID) else { continue }
            if newest == nil || transaction.purchaseDate > newest!.date {
                newest = (transaction.purchaseDate, result.jwsRepresentation)
            }
        }
        return newest?.jws
    }

    /// The signed-in dreamer's Supabase access token (the AI functions and
    /// `sync-subscription` key the entitlement to this user).
    private func currentAccessToken() async -> String? {
        #if canImport(Supabase)
        return (try? await SupabaseClientProvider.shared.auth.session)?.accessToken
        #else
        return nil
        #endif
    }

    /// The signed-in dreamer's Supabase user id (a UUID), attached to purchases as
    /// the StoreKit `appAccountToken` so server notifications resolve to this user.
    private func currentUserID() async -> UUID? {
        #if canImport(Supabase)
        return (try? await SupabaseClientProvider.shared.auth.session)?.user.id
        #else
        return nil
        #endif
    }
}
