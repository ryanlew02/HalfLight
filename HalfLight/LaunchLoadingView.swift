//
//  LaunchLoadingView.swift
//  HalfLight
//
//  The dreamy launch screen shown briefly at startup while every tab is built in
//  the background, so the first tap on each screen is instant. Reuses the night-sky
//  backdrop and the half-light brand mark — a slowly rotating moon-phase disc with
//  a breathing glow.
//

import SwiftUI

struct LaunchLoadingView: View {
    @State private var breathe = false
    @State private var glow = false
    @State private var spin = false

    var body: some View {
        ZStack {
            NightSkyBackground()

            VStack(spacing: 26) {
                ZStack {
                    // Soft radial halo that gently swells behind the mark.
                    Circle()
                        .fill(RadialGradient(
                            colors: [Color.dreamPrimary.opacity(0.5), .clear],
                            center: .center, startRadius: 2, endRadius: 120
                        ))
                        .frame(width: 260, height: 260)
                        .blur(radius: 6)
                        .scaleEffect(glow ? 1.12 : 0.86)
                        .opacity(glow ? 0.9 : 0.4)

                    // A large echo of the half-light brand mark, slowly turning like
                    // a moon phase.
                    Circle()
                        .fill(LinearGradient(
                            stops: [
                                .init(color: .dreamPrimary, location: 0.5),
                                .init(color: .dreamText.opacity(0.16), location: 0.5)
                            ],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(width: 84, height: 84)
                        .shadow(color: Color.dreamPrimary.opacity(0.55), radius: 22)
                        .rotationEffect(.degrees(spin ? 360 : 0))
                        .scaleEffect(breathe ? 1.05 : 0.97)
                }

                VStack(spacing: 10) {
                    Text("HALFLIGHT")
                        .font(.dreamMono(15, .medium))
                        .tracking(7)
                        .foregroundStyle(Color.dreamText)
                    Text("Gathering your dreams…")
                        .font(.dreamBody(13))
                        .foregroundStyle(.secondary)
                        .opacity(breathe ? 1 : 0.5)
                }
            }
            .padding(.bottom, 30)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                breathe = true
            }
            withAnimation(.easeInOut(duration: 1.7).repeatForever(autoreverses: true)) {
                glow = true
            }
            withAnimation(.linear(duration: 9).repeatForever(autoreverses: false)) {
                spin = true
            }
        }
    }
}

#Preview {
    LaunchLoadingView()
        .preferredColorScheme(.dark)
}
