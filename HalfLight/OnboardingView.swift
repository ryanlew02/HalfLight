//
//  OnboardingView.swift
//  HalfLight
//
//  First-launch introduction. A short paged tour of what the app does, ending on
//  a page that invites the dreamer to create an account — or skip and keep going
//  as a guest (the app is fully usable signed-out; an account only adds the
//  cross-device sync and the social feed). Shown once, gated by the
//  `didCompleteOnboarding` flag in `RootView`.
//

import SwiftUI

struct OnboardingView: View {
    @Environment(AuthService.self) private var auth

    /// Called when the dreamer chooses to continue without signing up. `RootView`
    /// records that onboarding is done and drops them into the app as a guest.
    let onContinueAsGuest: () -> Void

    @State private var page = 0
    @State private var showAuth = false
    /// Whether the account sheet opens on "create account" (Sign up) vs "sign in".
    @State private var authStartsOnSignUp = true

    private struct Page: Identifiable {
        let id = UUID()
        let symbol: String
        let title: String
        let body: String
    }

    private let pages: [Page] = [
        Page(
            symbol: "moon.stars.fill",
            title: "Welcome to HalfLight",
            body: "Dreams fade within minutes of waking. HalfLight helps you catch them before they slip away."
        ),
        Page(
            symbol: "waveform",
            title: "Capture every dream",
            body: "Type or speak your dream the moment you wake. Let AI name it, tag it, and reveal what it might mean."
        ),
        Page(
            symbol: "flame.fill",
            title: "Build the habit",
            body: "Keep your streak alive, complete daily quests, and level up as your dream journal grows."
        ),
        Page(
            symbol: "eye.fill",
            title: "Learn to lucid dream",
            body: "Follow the Lucid Path — guided lessons and techniques to become aware inside your dreams."
        ),
        Page(
            symbol: "globe.americas.fill",
            title: "Share the journey",
            body: "Post dreams to the community feed and follow other dreamers — or keep everything private. It's up to you."
        ),
    ]

    private var isLastPage: Bool { page == pages.count - 1 }

    var body: some View {
        ZStack {
            NightSkyBackground()

            VStack(spacing: 0) {
                topBar

                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { index, item in
                        pageContent(item)
                            .tag(index)
                    }
                }
                #if os(iOS)
                .tabViewStyle(.page(indexDisplayMode: .never))
                #endif
                .animation(.easeInOut(duration: 0.3), value: page)

                bottomControls
            }
        }
        .sheet(isPresented: $showAuth) {
            AuthView(startInSignUp: authStartsOnSignUp)
        }
    }

    // MARK: - Top bar (Skip)

    private var topBar: some View {
        HStack {
            Spacer()
            // A quick exit to the app as a guest — mirrors "Sign up later" on the
            // final page. Hidden there so the deliberate choice stands alone.
            if !isLastPage {
                Button("Skip") {
                    SoundManager.shared.play(.tap)
                    onContinueAsGuest()
                }
                .font(.dreamBody(15, .semibold))
                .foregroundStyle(Color.dreamText.opacity(0.6))
            }
        }
        .frame(height: 24)
        .padding(.horizontal, DreamMetric.screen)
        .padding(.top, DreamMetric.sm)
    }

    // MARK: - Page

    private func pageContent(_ item: Page) -> some View {
        VStack(spacing: DreamMetric.xl) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.dreamPrimary.opacity(0.12))
                    .frame(width: 132, height: 132)
                Circle()
                    .strokeBorder(Color.dreamMoonRim.opacity(0.35), lineWidth: 1)
                    .frame(width: 132, height: 132)
                Image(systemName: item.symbol)
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(Color.dreamPrimary)
            }
            .shadow(color: Color.dreamPrimary.opacity(0.25), radius: 30)

            VStack(spacing: DreamMetric.md) {
                Text(item.title)
                    .font(.dreamDisplay(30))
                    .foregroundStyle(Color.dreamText)
                    .multilineTextAlignment(.center)

                Text(item.body)
                    .font(.dreamBody(16))
                    .foregroundStyle(Color.dreamText.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .dreamBodyLineSpacing()
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
            Spacer()
        }
        .padding(.horizontal, DreamMetric.xl)
    }

    // MARK: - Bottom controls

    private var bottomControls: some View {
        VStack(spacing: DreamMetric.lg) {
            pageDots

            if isLastPage {
                VStack(spacing: DreamMetric.sm) {
                    Button {
                        authStartsOnSignUp = true
                        showAuth = true
                    } label: {
                        Text("Sign up")
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    Button {
                        SoundManager.shared.play(.tap)
                        onContinueAsGuest()
                    } label: {
                        Text("Sign up later")
                    }
                    .buttonStyle(GhostButtonStyle())

                    Button {
                        authStartsOnSignUp = false
                        showAuth = true
                    } label: {
                        Text("I already have an account")
                            .font(.dreamBody(14, .semibold))
                            .foregroundStyle(Color.dreamPrimary)
                            .padding(.top, DreamMetric.xs)
                    }
                }
            } else {
                Button {
                    SoundManager.shared.play(.tap)
                    withAnimation { page += 1 }
                } label: {
                    Text("Continue")
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(.horizontal, DreamMetric.screen)
        .padding(.bottom, DreamMetric.xl)
    }

    private var pageDots: some View {
        HStack(spacing: DreamMetric.sm) {
            ForEach(pages.indices, id: \.self) { index in
                Capsule()
                    .fill(index == page ? Color.dreamPrimary : Color.dreamText.opacity(0.2))
                    .frame(width: index == page ? 22 : 7, height: 7)
                    .animation(.easeInOut(duration: 0.25), value: page)
            }
        }
    }
}

#Preview {
    OnboardingView(onContinueAsGuest: {})
        .environment(AuthService())
}
