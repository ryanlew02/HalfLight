//
//  LevelUpView.swift
//  HalfLight
//
//  The full-screen celebration shown when the dreamer levels up. It mirrors the
//  XP claim animation — a burst of rays and sparkles — but the hero is the new
//  rank they've reached. A tap anywhere dismisses it.
//

import SwiftUI

struct LevelUpView: View {
    let reward: ClaimReward
    let onDismiss: () -> Void

    /// Drives the repeating outward burst of rays and sparkles.
    @State private var burst = false
    /// Drives the one-shot spring-in of the central readout.
    @State private var core = false

    private let rayCount = 16
    private let sparkleCount = 10

    var body: some View {
        ZStack {
            backdrop

            rays
            sparkles
            coreReadout

            VStack {
                Spacer()
                Text("Tap to continue")
                    .font(.dreamMono(11))
                    .tracking(1.5)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.white.opacity(0.5))
                    .opacity(core ? 1 : 0)
                    .padding(.bottom, 56)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onDismiss() }
        .onAppear {
            SoundManager.shared.play(.levelUp)
            withAnimation(.spring(response: 0.55, dampingFraction: 0.55).delay(0.05)) {
                core = true
            }
            withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
                burst = true
            }
        }
    }

    private var backdrop: some View {
        Color.black.opacity(0.78)
            .ignoresSafeArea()
            .overlay(
                RadialGradient(
                    colors: [Color.dreamPrimary.opacity(0.30), .clear],
                    center: .center, startRadius: 0, endRadius: 340
                )
                .ignoresSafeArea()
                .scaleEffect(core ? 1 : 0.6)
                .opacity(core ? 1 : 0)
            )
    }

    private var rays: some View {
        ForEach(0..<rayCount, id: \.self) { i in
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color.dreamPrimary, Color.dreamAccent],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: 4, height: burst ? 80 : 6)
                .offset(y: burst ? -220 : -72)
                .opacity(burst ? 0 : 0.9)
                .rotationEffect(.degrees(Double(i) / Double(rayCount) * 360))
        }
        .opacity(core ? 1 : 0)
    }

    private var sparkles: some View {
        ForEach(0..<sparkleCount, id: \.self) { i in
            let angle = Double(i) / Double(sparkleCount) * 2 * .pi
            Image(systemName: i.isMultiple(of: 2) ? "sparkle" : "star.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(i.isMultiple(of: 2) ? Color.dreamAccent : Color.dreamPrimary)
                .offset(
                    x: burst ? cos(angle) * 175 : 0,
                    y: burst ? sin(angle) * 175 : 0
                )
                .scaleEffect(burst ? 0.3 : 1)
                .opacity(burst ? 0 : 1)
        }
        .opacity(core ? 1 : 0)
    }

    private var coreReadout: some View {
        VStack(spacing: 12) {
            Text(reward.headline)
                .font(.dreamMono(12, .semibold))
                .tracking(2.5)
                .textCase(.uppercase)
                .foregroundStyle(Color.dreamAccent)

            // Rank crest.
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.dreamPrimary, Color.dreamAccent],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                    .shadow(color: Color.dreamPrimary.opacity(0.6), radius: 18)
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(.white)
            }
            .padding(.vertical, 4)

            // The new rank — the hero of this screen.
            Text(reward.title)
                .font(.dreamSerif(38))
                .multilineTextAlignment(.center)
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.white, Color.dreamPrimary],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .shadow(color: Color.dreamPrimary.opacity(0.6), radius: 18)

            Text("Level \(reward.level)")
                .font(.dreamSerif(22))
                .foregroundStyle(Color.white.opacity(0.8))
        }
        .padding(.horizontal, 32)
        .scaleEffect(core ? 1 : 0.3)
        .opacity(core ? 1 : 0)
    }
}

#Preview {
    LevelUpView(
        reward: ClaimReward(kind: .levelUp, title: "Lucid Initiate", headline: "Level Up", level: 15)
    ) {}
}
