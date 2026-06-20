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
            // A single top-anchored radial wash: lightest at the crown of the
            // screen, settling to the deep base tone toward the bottom. Replaces
            // the old top→bottom linear gradient for a more celestial fall-off.
            RadialGradient(
                colors: [.dreamSurface, .dreamBase, .dreamBaseDeep],
                center: .init(x: 0.5, y: -0.08),
                startRadius: 0,
                endRadius: 760
            )

            // A soft warm glow at the very top-center, like a covered moon.
            RadialGradient(
                colors: [Color.dreamPrimary.opacity(scheme == .dark ? 0.16 : 0.16), .clear],
                center: .init(x: 0.5, y: -0.02),
                startRadius: 0,
                endRadius: 280
            )

            // Sparse starfield — atmosphere, not data. Dark mode only; light mode
            // stays clean with just the top wash.
            if scheme == .dark {
                StarField()
            }
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
    let color: Color
}

/// A sparse scatter of tiny stars — mostly soft `dreamText`, with a couple in
/// the warm accent tones — placed deterministically so they don't reshuffle.
private struct StarField: View {
    private let starCount = 14

    private var stars: [Star] {
        var rng = SeededGenerator(seed: 42)
        // Most stars are the soft text tone; sprinkle a couple of warm accents.
        let accentEvery = 6
        return (0..<starCount).map { index in
            let color: Color = index % accentEvery == 0
                ? (index % (accentEvery * 2) == 0 ? .dreamPrimary : .dreamAccent)
                : .dreamText
            return Star(
                point: CGPoint(x: .random(in: 0.04...0.96, using: &rng),
                               y: .random(in: 0.04...0.92, using: &rng)),
                radius: .random(in: 0.75...1.1, using: &rng),
                opacity: .random(in: 0.28...0.5, using: &rng),
                color: color
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
                    with: .color(star.color.opacity(star.opacity))
                )
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
