//
//  LaunchLoadingView.swift
//  HalfLight
//
//  The dreamy launch screen shown briefly at startup while every tab is built in
//  the background, so the first tap on each screen is instant. Reuses the night-sky
//  backdrop and the half-light brand mark — a slowly rotating moon-phase disc with
//  a breathing glow.
//
//  The mark animates with Core Animation, not SwiftUI: CA animations run on the
//  system render server, so the spin stays fluid while the app's main thread is
//  busy prebuilding tabs. Anything main-thread-driven (TimelineView, SwiftUI
//  repeatForever) drops to a handful of frames during that work and the disc
//  visibly teleports between positions.
//

import SwiftUI

struct LaunchLoadingView: View {
    /// Drives the caption's gentle fade. Main-thread animated, so under launch
    /// load it may pause — imperceptible for a slow opacity change, unlike the
    /// disc's rotation.
    @State private var breathe = false

    var body: some View {
        ZStack {
            NightSkyBackground()

            VStack(spacing: 26) {
                #if canImport(UIKit)
                LaunchMarkView()
                    .frame(width: 260, height: 260)
                #else
                StaticLaunchMark()
                #endif

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
        }
    }
}

#if canImport(UIKit)
import UIKit

/// The animated brand mark — swelling halo, breathing glow, and the turning
/// half-lit disc — drawn with CA layers whose animations live on the render
/// server, immune to main-thread stalls.
private struct LaunchMarkView: UIViewRepresentable {
    /// Read so SwiftUI re-calls `updateUIView` when the scheme flips and the
    /// layer colors can re-resolve.
    @Environment(\.colorScheme) private var colorScheme

    func makeUIView(context: Context) -> LaunchMarkUIView {
        LaunchMarkUIView()
    }

    func updateUIView(_ view: LaunchMarkUIView, context: Context) {
        view.refreshColors()
    }
}

final class LaunchMarkUIView: UIView {
    private static let discDiameter: CGFloat = 84

    /// Soft radial halo that swells behind the mark.
    private let halo = CAGradientLayer()
    /// The disc's colored glow — a solid circle hidden behind the disc whose
    /// shadow provides the bloom.
    private let glow = CALayer()
    /// The half-lit disc: a hard two-stop horizontal gradient in a circle.
    private let disc = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false

        halo.type = .radial
        halo.startPoint = CGPoint(x: 0.5, y: 0.5)
        halo.endPoint = CGPoint(x: 1, y: 1)
        layer.addSublayer(halo)

        let discSize = CGSize(width: Self.discDiameter, height: Self.discDiameter)
        glow.bounds = CGRect(origin: .zero, size: discSize)
        glow.cornerRadius = Self.discDiameter / 2
        glow.shadowOpacity = 0.55
        glow.shadowRadius = 22
        glow.shadowOffset = .zero
        glow.shadowPath = UIBezierPath(ovalIn: glow.bounds).cgPath
        layer.addSublayer(glow)

        disc.bounds = CGRect(origin: .zero, size: discSize)
        disc.cornerRadius = Self.discDiameter / 2
        disc.masksToBounds = true
        disc.startPoint = CGPoint(x: 0, y: 0.5)
        disc.endPoint = CGPoint(x: 1, y: 0.5)
        // Two hard stops at the middle: lit half, shadowed half.
        disc.locations = [0, 0.5, 0.5, 1]
        layer.addSublayer(disc)

        refreshColors()

        // CA animations are removed when the app backgrounds; restore them on
        // return so the mark never sits frozen.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(addAnimations),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Position via bounds+position, never `frame`: these layers carry
        // animated transforms, and setting `frame` on a transformed layer
        // misplaces it. Disable implicit actions so layout can't animate.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        halo.bounds = bounds
        halo.position = center
        glow.position = center
        disc.position = center
        CATransaction.commit()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { addAnimations() }
    }

    /// Re-resolve the adaptive palette into the layers (called on scheme flips).
    func refreshColors() {
        let primary = UIColor(Color.dreamPrimary).resolvedColor(with: traitCollection)
        let text = UIColor(Color.dreamText).resolvedColor(with: traitCollection)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        halo.colors = [
            primary.withAlphaComponent(0.5).cgColor,
            primary.withAlphaComponent(0).cgColor,
        ]
        glow.backgroundColor = primary.cgColor
        glow.shadowColor = primary.cgColor
        disc.colors = [
            primary.cgColor, primary.cgColor,
            text.withAlphaComponent(0.16).cgColor, text.withAlphaComponent(0.16).cgColor,
        ]
        CATransaction.commit()
    }

    @objc private func addAnimations() {
        guard disc.animation(forKey: "spin") == nil else { return }

        // One slow, perfectly linear turn.
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = 2 * Double.pi
        spin.duration = 12
        spin.repeatCount = .infinity
        spin.timingFunction = CAMediaTimingFunction(name: .linear)
        disc.add(spin, forKey: "spin")

        // The disc (and its glow) breathe together.
        let breathe = CABasicAnimation(keyPath: "transform.scale")
        breathe.fromValue = 0.97
        breathe.toValue = 1.05
        breathe.duration = 2.2
        breathe.autoreverses = true
        breathe.repeatCount = .infinity
        breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        disc.add(breathe, forKey: "breathe")
        glow.add(breathe, forKey: "breathe")

        // The halo swells and brightens on its own slightly offset rhythm.
        let swell = CABasicAnimation(keyPath: "transform.scale")
        swell.fromValue = 0.86
        swell.toValue = 1.12
        let brighten = CABasicAnimation(keyPath: "opacity")
        brighten.fromValue = 0.4
        brighten.toValue = 0.9
        let haloGroup = CAAnimationGroup()
        haloGroup.animations = [swell, brighten]
        haloGroup.duration = 1.7
        haloGroup.autoreverses = true
        haloGroup.repeatCount = .infinity
        haloGroup.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        halo.add(haloGroup, forKey: "swell")
    }
}
#else
/// Non-UIKit fallback: the mark at rest.
private struct StaticLaunchMark: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [Color.dreamPrimary.opacity(0.5), .clear],
                    center: .center, startRadius: 2, endRadius: 120
                ))
                .frame(width: 260, height: 260)

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
        }
    }
}
#endif

#Preview {
    LaunchLoadingView()
        .preferredColorScheme(.dark)
}
