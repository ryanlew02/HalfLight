//
//  NightSkyBackground.swift
//  HalfLight
//
//  Atmospheric backdrop for the app: the base gradient layered with a soft
//  radial moonglow, a faint star field, and low-opacity grain. Stars and grain
//  are generated deterministically so they don't reshuffle on every redraw.
//

import SwiftUI

struct NightSkyBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.dreamBase, .dreamSurface],
                startPoint: .top,
                endPoint: .bottom
            )

            // Soft moonglow anchored to the top-trailing corner.
            RadialGradient(
                colors: [Color.dreamPrimary.opacity(scheme == .dark ? 0.22 : 0.18), .clear],
                center: .init(x: 0.85, y: 0.08),
                startRadius: 0,
                endRadius: 420
            )

            // A second, cooler glow at the bottom-leading corner so the lower
            // half carries the same atmosphere as the top instead of going flat.
            RadialGradient(
                colors: [Color.dreamAccent.opacity(scheme == .dark ? 0.20 : 0.16), .clear],
                center: .init(x: 0.12, y: 0.96),
                startRadius: 0,
                endRadius: 440
            )

            StarField(starCount: scheme == .dark ? 80 : 40)
                .opacity(scheme == .dark ? 1 : 0.5)

            GrainOverlay()
                .opacity(scheme == .dark ? 0.06 : 0.035)
                .blendMode(scheme == .dark ? .screen : .multiply)
        }
        .ignoresSafeArea()
    }
}

/// A simple, seedable pseudo-random generator so star/grain placement is stable
/// across redraws (a fresh `SystemRandomNumberGenerator` would jitter each frame).
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

private struct Star {
    let point: CGPoint     // normalized 0...1
    let radius: CGFloat
    let opacity: Double
}

private struct StarField: View {
    let starCount: Int

    private var stars: [Star] {
        var rng = SeededGenerator(seed: 42)
        return (0..<starCount).map { _ in
            Star(
                point: CGPoint(x: .random(in: 0...1, using: &rng),
                               y: .random(in: 0...1, using: &rng)),
                radius: .random(in: 0.5...1.6, using: &rng),
                opacity: .random(in: 0.2...0.9, using: &rng)
            )
        }
    }

    var body: some View {
        Canvas { context, size in
            for star in stars {
                let rect = CGRect(
                    x: star.point.x * size.width - star.radius,
                    y: star.point.y * size.height - star.radius,
                    width: star.radius * 2,
                    height: star.radius * 2
                )
                context.fill(
                    Path(ellipseIn: rect),
                    with: .color(.white.opacity(star.opacity))
                )
            }
        }
    }
}

/// Fine film grain, drawn as scattered specks. Kept light for performance.
private struct GrainOverlay: View {
    private let speckCount = 280

    private var specks: [CGPoint] {
        var rng = SeededGenerator(seed: 7)
        return (0..<speckCount).map { _ in
            CGPoint(x: .random(in: 0...1, using: &rng),
                    y: .random(in: 0...1, using: &rng))
        }
    }

    var body: some View {
        Canvas { context, size in
            for p in specks {
                let rect = CGRect(x: p.x * size.width, y: p.y * size.height, width: 1.2, height: 1.2)
                context.fill(Path(rect), with: .color(.white))
            }
        }
    }
}

#Preview("Dark") {
    NightSkyBackground().preferredColorScheme(.dark)
}

#Preview("Light") {
    NightSkyBackground().preferredColorScheme(.light)
}
