//
//  PaywallView.swift
//  HalfLight
//
//  Presented when a non-subscriber taps an AI feature (analyze, auto-tag,
//  auto-title). Sells "HalfLight Pro" and runs the purchase via
//  `SubscriptionManager`. Styled with the shared DesignSystem so it feels native
//  to the app rather than a generic store sheet.
//

import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(SubscriptionManager.self) private var subscriptions
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    /// The Apple-required legal links shown at the foot of the sheet.
    private let termsURL = URL(string: "https://halflightdream.com/terms.html")!
    private let privacyURL = URL(string: "https://halflightdream.com/privacy.html")!

    /// Which plan is selected to buy; defaults to the yearly (best value) plan.
    @State private var selectedYearly = true

    /// Presents Apple's offer-code redemption sheet (for free/discount codes you
    /// create in App Store Connect). A successful redeem creates a transaction the
    /// `SubscriptionManager` listener picks up, which unlocks and dismisses here.
    @State private var showRedeem = false

    /// Pro's features all run server-side against the dreamer's account, so a
    /// guest has to sign in before there's anything to attach a purchase to.
    @State private var showAuth = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DreamMetric.xl) {
                    header
                    featureList
                    plans
                    purchaseButton
                    redeemButton
                    legalFooter
                }
                .padding(DreamMetric.screen)
            }
            .scrollContentBackground(.hidden)
            .background { DreamBackground() }
            .offerCodeRedemption(isPresented: $showRedeem) { _ in
                // Apple's sheet reports invalid codes itself; a successful redeem
                // creates a transaction the SubscriptionManager listener picks up
                // to unlock and sync, which dismisses this paywall.
            }
            .sheet(isPresented: $showAuth) { AuthView(startInSignUp: true) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .tint(.dreamPrimary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Restore") {
                        Task { await subscriptions.restore() }
                    }
                    .tint(.dreamPrimary)
                    .disabled(subscriptions.isPurchasing)
                }
            }
        }
        .task {
            // Don't greet a re-opened paywall with the last attempt's error, and
            // pick up prices if an earlier load failed.
            subscriptions.clearError()
            if subscriptions.productsUnavailable {
                await subscriptions.loadProducts()
            }
            // Trial eligibility is per-Apple-ID and can change between openings
            // (a lapsed subscriber is no longer eligible).
            await subscriptions.refreshTrialEligibility()
            selectPurchasablePlan()
        }
        .onChange(of: subscriptions.isSubscribed) { _, subscribed in
            // Only close once Pro is actually usable. An entitlement restored
            // while signed out still has no account behind it, and closing on it
            // would hide the message saying so.
            guard subscribed, auth.isSignedIn else { return }
            SoundManager.shared.play(.reward)
            dismiss()
        }
        .onChange(of: auth.isSignedIn) { _, signedIn in
            guard signedIn else { return }
            Task {
                // Signing in can reveal an entitlement this Apple ID already had
                // (RootView pushes it to the server); there's then nothing to sell.
                await subscriptions.refreshTrialEligibility()
                if subscriptions.isSubscribed {
                    SoundManager.shared.play(.reward)
                    dismiss()
                }
            }
        }
    }

    /// Keep the selection on a plan that actually loaded, so the buy button can
    /// never be pointed at a missing product.
    private func selectPurchasablePlan() {
        if selectedYearly && subscriptions.yearly == nil, subscriptions.monthly != nil {
            selectedYearly = false
        } else if !selectedYearly && subscriptions.monthly == nil, subscriptions.yearly != nil {
            selectedYearly = true
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: DreamMetric.sm) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(Color.dreamPrimary)
            Text("HalfLight Pro")
                .font(.dreamLargeTitle)
                .foregroundStyle(Color.dreamText)
            Text("Unlock AI dream analysis, auto-tags, and AI-written titles.")
                .font(.dreamBodyText)
                .foregroundStyle(Color.dreamSubtle)
                .multilineTextAlignment(.center)
        }
        .padding(.top, DreamMetric.md)
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: DreamMetric.md) {
            feature("wand.and.stars", "Analyze with AI", "A grounded interpretation of what each dream may mean.")
            feature("tag", "Auto-tag", "Surface the themes and symbols in your dreams automatically.")
            feature("text.quote", "AI titles", "Turn a sleepy description into an evocative title.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DreamMetric.lg)
        .dreamCard()
    }

    private func feature(_ icon: String, _ title: LocalizedStringKey, _ subtitle: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: DreamMetric.md) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(Color.dreamPrimary)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.dreamGrotesk(15, .semibold))
                    .foregroundStyle(Color.dreamText)
                Text(subtitle)
                    .font(.dreamSubtext)
                    .foregroundStyle(Color.dreamSubtle)
            }
        }
    }

    @ViewBuilder
    private var plans: some View {
        VStack(spacing: DreamMetric.md) {
            // Every price shown comes from the loaded `Product`, so it's always in
            // the dreamer's own storefront and currency. If the App Store didn't
            // answer we show nothing rather than a made-up dollar figure.
            if let yearly = subscriptions.yearly {
                planCard(
                    isYearly: true,
                    title: "Yearly",
                    price: yearly.displayPrice,
                    period: "per year",
                    badge: trialBadge,
                    caption: trialOffer == nil
                        ? "Best value — billed yearly."
                        : "Best value — billed yearly after the trial."
                )
            }
            if let monthly = subscriptions.monthly {
                planCard(
                    isYearly: false,
                    title: "Monthly",
                    price: monthly.displayPrice,
                    period: "per month",
                    badge: nil,
                    caption: "Flexible — cancel anytime."
                )
            }
            if subscriptions.productsUnavailable {
                Text("Subscription options couldn't be loaded right now.")
                    .font(.dreamBodyText)
                    .foregroundStyle(Color.dreamSubtle)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(DreamMetric.lg)
                    .dreamCard()
            }
        }
    }

    /// The yearly plan's introductory offer — `nil` unless this Apple ID can
    /// still use it, so a returning subscriber is never promised a second trial.
    private var trialOffer: Product.SubscriptionOffer? { subscriptions.yearlyTrialOffer }

    /// Badge copy that matches the offer Apple will actually apply at checkout.
    private var trialBadge: LocalizedStringKey? {
        guard let offer = trialOffer else { return nil }
        let isOneWeek = offer.period.unit == .week && offer.period.value == 1
        return isOneWeek ? "1 WEEK FREE" : "FREE TRIAL"
    }

    private func planCard(
        isYearly: Bool,
        title: LocalizedStringKey,
        price: String,
        period: LocalizedStringKey,
        badge: LocalizedStringKey?,
        caption: LocalizedStringKey
    ) -> some View {
        let selected = selectedYearly == isYearly
        return Button {
            SoundManager.shared.play(.tap)
            selectedYearly = isYearly
        } label: {
            HStack(spacing: DreamMetric.md) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(selected ? Color.dreamPrimary : Color.dreamFaint)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: DreamMetric.sm) {
                        Text(title)
                            .font(.dreamGrotesk(16, .semibold))
                            .foregroundStyle(Color.dreamText)
                        if let badge {
                            Text(badge)
                                .font(.dreamEyebrow)
                                .dreamEyebrow()
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.dreamPrimary.opacity(0.18), in: .capsule)
                                .foregroundStyle(Color.dreamPrimary)
                        }
                    }
                    Text(caption)
                        .font(.dreamSubtext)
                        .foregroundStyle(Color.dreamSubtle)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text(price)
                        .font(.dreamGrotesk(16, .semibold))
                        .foregroundStyle(Color.dreamText)
                    Text(period)
                        .font(.dreamCaption)
                        .foregroundStyle(Color.dreamFaint)
                }
            }
            .padding(DreamMetric.lg)
            .background(Color.dreamSurface, in: .rect(cornerRadius: DreamMetric.controlRadius))
            .overlay(
                RoundedRectangle(cornerRadius: DreamMetric.controlRadius)
                    .strokeBorder(selected ? Color.dreamPrimary : Color.dreamText.opacity(0.08),
                                  lineWidth: selected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var purchaseButton: some View {
        VStack(spacing: DreamMetric.sm) {
            Button {
                SoundManager.shared.play(.tap)
                if !auth.isSignedIn {
                    showAuth = true
                } else if subscriptions.productsUnavailable {
                    Task { await subscriptions.loadProducts(); selectPurchasablePlan() }
                } else {
                    Task { await buySelected() }
                }
            } label: {
                HStack(spacing: DreamMetric.sm) {
                    if subscriptions.isPurchasing { ProgressView().tint(.dreamOnPrimary) }
                    Text(primaryButtonTitle)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(subscriptions.isPurchasing || (auth.isSignedIn && selectedProduct == nil && !subscriptions.productsUnavailable))

            if let error = subscriptions.errorMessage {
                Text(error)
                    .font(.dreamSubtext)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            if let terms = billingTerms {
                Text(terms)
                    .font(.dreamCaption)
                    .foregroundStyle(Color.dreamFaint)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var primaryButtonTitle: LocalizedStringKey {
        // The AI features are gated on the server by account, so a guest has to
        // sign in before a purchase can unlock anything. Say so on the button
        // rather than taking the money and failing afterwards.
        if !auth.isSignedIn { return "Sign In to Subscribe" }
        if subscriptions.productsUnavailable { return "Try Again" }
        guard selectedYearly, let offer = trialOffer else { return "Subscribe" }
        let isOneWeek = offer.period.unit == .week && offer.period.value == 1
        return isOneWeek ? "Start 1-Week Free Trial" : "Start Free Trial"
    }

    /// The price-and-renewal line under the button. Built from the real product
    /// price and the trial the App Store will actually grant, so it never
    /// promises a free week to someone who's already had one. `nil` while there
    /// are no prices to quote.
    private var billingTerms: String? {
        if !auth.isSignedIn {
            return localized("HalfLight Pro unlocks AI on your account, so it works on every device you sign in to.")
        }
        guard let product = selectedProduct else { return nil }
        if selectedYearly {
            guard let offer = trialOffer else {
                return localized("%@/year. Cancel anytime.", product.displayPrice)
            }
            let isOneWeek = offer.period.unit == .week && offer.period.value == 1
            return isOneWeek
                ? localized("7 days free, then %@/year. Cancel anytime.", product.displayPrice)
                : localized("Free trial, then %@/year. Cancel anytime.", product.displayPrice)
        }
        return localized("%@/month. Cancel anytime.", product.displayPrice)
    }

    /// The product the buy button would purchase right now.
    private var selectedProduct: Product? {
        selectedYearly ? subscriptions.yearly : subscriptions.monthly
    }

    private var redeemButton: some View {
        Button {
            SoundManager.shared.play(.tap)
            showRedeem = true
        } label: {
            Text("Have a code? Redeem")
                .font(.dreamBody(14, .semibold))
                .foregroundStyle(Color.dreamPrimary)
        }
        .buttonStyle(.plain)
    }

    private var legalFooter: some View {
        VStack(spacing: DreamMetric.xs) {
            Text("Payment is charged to your Apple ID. Subscriptions renew automatically unless cancelled at least 24 hours before the end of the period. Manage or cancel in your App Store account settings.")
                .font(.dreamCaption)
                .foregroundStyle(Color.dreamFaint)
                .multilineTextAlignment(.center)
            HStack(spacing: DreamMetric.sm) {
                Link("Terms of Use", destination: termsURL)
                Text("·").foregroundStyle(Color.dreamFaint)
                Link("Privacy Policy", destination: privacyURL)
            }
            .font(.dreamCaption)
            .tint(.dreamPrimary)
        }
    }

    // MARK: - Actions

    private func buySelected() async {
        guard let product = selectedProduct else {
            await subscriptions.loadProducts()
            selectPurchasablePlan()
            return
        }
        await subscriptions.purchase(product)
    }
}
