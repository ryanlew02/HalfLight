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

    /// True while a purchase or restore is in flight, to drive button spinners.
    private(set) var isPurchasing = false
    /// A user-facing message when a purchase fails; `nil` when there's no error.
    private(set) var errorMessage: String?

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
    func loadProducts() async {
        do {
            let products = try await Product.products(for: ProductID.all)
            monthly = products.first { $0.id == ProductID.monthly }
            yearly = products.first { $0.id == ProductID.yearly }
        } catch {
            errorMessage = "Couldn't load subscription options. Check your connection."
        }
    }

    /// Buy a product. Returns true when the purchase completes and unlocks Pro.
    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        errorMessage = nil
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            // Tag the purchase with the signed-in user's id so Apple's server
            // notifications (which carry no Supabase JWT) can map renewals and
            // refunds back to this dreamer via `appAccountToken`.
            var options: Set<Product.PurchaseOption> = []
            if let userID = await currentUserID() {
                options.insert(.appAccountToken(userID))
            }
            let result = try await product.purchase(options: options)
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await refreshEntitlement()
                await syncToServer()
                await transaction.finish()
                return isSubscribed
            case .userCancelled:
                return false
            case .pending:
                // Ask-to-Buy / SCA: resolves later via the updates listener.
                errorMessage = "Your purchase is pending approval."
                return false
            @unknown default:
                return false
            }
        } catch {
            errorMessage = "Purchase failed. Please try again."
            return false
        }
    }

    /// Restore purchases — asks the App Store to re-sync, then recomputes.
    func restore() async {
        errorMessage = nil
        isPurchasing = true
        defer { isPurchasing = false }
        try? await AppStore.sync()
        await refreshEntitlement()
        await syncToServer()
        if !isSubscribed {
            errorMessage = "No active subscription found to restore."
        }
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
                guard let self else { continue }
                if let transaction = try? self.checkVerified(update) {
                    await self.refreshEntitlement()
                    await self.syncToServer()
                    await transaction.finish()
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

    /// POST the latest verified transaction's signed JWS to the `sync-subscription`
    /// edge function so the server records the entitlement. Best-effort: the App
    /// Store Server Notifications webhook is the durable backstop, so failures here
    /// are silent (the listener will retry on the next update).
    private func syncToServer() async {
        guard let jws = await latestTransactionJWS() else { return }
        guard let accessToken = await currentAccessToken() else { return }

        let endpoint = SupabaseConfig.url
            .appendingPathComponent("functions/v1/sync-subscription")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONEncoder().encode(["jws": jws])

        _ = try? await URLSession.shared.data(for: request)
    }

    /// The signed JWS of the most recent verified Pro transaction, used by the
    /// server to verify the subscription against Apple's public keys.
    private func latestTransactionJWS() async -> String? {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               ProductID.all.contains(transaction.productID) {
                return result.jwsRepresentation
            }
        }
        return nil
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
