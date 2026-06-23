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
    @Environment(\.dismiss) private var dismiss

    /// The Apple-required legal links shown at the foot of the sheet.
    private let termsURL = URL(string: "https://thelanternhours.com/terms")!
    private let privacyURL = URL(string: "https://thelanternhours.com/privacy")!

    /// Which plan is selected to buy; defaults to the yearly (best value) plan.
    @State private var selectedYearly = true

    /// Presents Apple's offer-code redemption sheet (for free/discount codes you
    /// create in App Store Connect). A successful redeem creates a transaction the
    /// `SubscriptionManager` listener picks up, which unlocks and dismisses here.
    @State private var showRedeem = false

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
                }
            }
        }
        .onChange(of: subscriptions.isSubscribed) { _, subscribed in
            if subscribed {
                SoundManager.shared.play(.reward)
                dismiss()
            }
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

    private func feature(_ icon: String, _ title: String, _ subtitle: String) -> some View {
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

    private var plans: some View {
        VStack(spacing: DreamMetric.md) {
            planCard(
                isYearly: true,
                title: "Yearly",
                price: subscriptions.yearly?.displayPrice ?? "$49.99",
                period: "per year",
                badge: "1 WEEK FREE",
                caption: "Best value — billed yearly after the trial."
            )
            planCard(
                isYearly: false,
                title: "Monthly",
                price: subscriptions.monthly?.displayPrice ?? "$9.99",
                period: "per month",
                badge: nil,
                caption: "Flexible — cancel anytime."
            )
        }
    }

    private func planCard(
        isYearly: Bool,
        title: String,
        price: String,
        period: String,
        badge: String?,
        caption: String
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
                Task { await buySelected() }
            } label: {
                HStack(spacing: DreamMetric.sm) {
                    if subscriptions.isPurchasing { ProgressView().tint(.dreamOnPrimary) }
                    Text(selectedYearly ? "Start 1-Week Free Trial" : "Subscribe")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(subscriptions.isPurchasing)

            if let error = subscriptions.errorMessage {
                Text(error)
                    .font(.dreamSubtext)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Text(selectedYearly
                 ? "7 days free, then \(subscriptions.yearly?.displayPrice ?? "$49.99")/year. Cancel anytime."
                 : "\(subscriptions.monthly?.displayPrice ?? "$9.99")/month. Cancel anytime.")
                .font(.dreamCaption)
                .foregroundStyle(Color.dreamFaint)
                .multilineTextAlignment(.center)
        }
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
        let product = selectedYearly ? subscriptions.yearly : subscriptions.monthly
        guard let product else {
            await subscriptions.loadProducts()
            return
        }
        await subscriptions.purchase(product)
    }
}
