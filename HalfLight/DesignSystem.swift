//
//  DesignSystem.swift
//  HalfLight
//
//  Shared visual language: the rounded display type, the elevated card surface,
//  and the two button styles. Centralizing these keeps spacing, radius, and
//  weight consistent instead of scattered magic numbers per-screen.
//

import SwiftUI

// MARK: - Spacing & radius scale

enum DreamMetric {
    /// 8-pt spacing scale. Use these instead of ad-hoc numbers.
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32

    /// Screen edge inset.
    static let screen: CGFloat = 20

    /// Card / surface corner radius.
    static let cardRadius: CGFloat = 24
    /// Buttons, pills, inputs.
    static let controlRadius: CGFloat = 16
}

// MARK: - Typography

extension Font {
    /// Thick, rounded display face — playful and friendly, used for titles,
    /// section labels, dream titles, and stat numbers.
    static func dreamDisplay(_ size: CGFloat, _ weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// Rounded body face for supporting copy, keeping the soft tone cohesive.
    static func dreamBody(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

// MARK: - Elevated surface

/// The single card treatment used across the app: filled surface, soft
/// shadow for real depth (no hairline borders), rounded corners.
struct DreamSurfaceModifier: ViewModifier {
    var radius: CGFloat = DreamMetric.cardRadius
    var glow: Color? = nil

    func body(content: Content) -> some View {
        content
            .background(Color.dreamSurface, in: .rect(cornerRadius: radius))
            .shadow(color: .black.opacity(0.10), radius: 18, x: 0, y: 10)
            // A soft, very diffuse bloom — low opacity over a wide radius so it
            // reads as ambient light bleeding into the screen rather than a
            // tight halo hugging the card edge.
            .shadow(color: (glow ?? .clear).opacity(glow == nil ? 0 : 0.16), radius: 55, x: 0, y: 4)
    }
}

extension View {
    /// Apply the standard elevated card surface. Pass `glow` to add a soft
    /// colored halo (used to make the latest-dream hero feel lit from within).
    func dreamCard(radius: CGFloat = DreamMetric.cardRadius, glow: Color? = nil) -> some View {
        modifier(DreamSurfaceModifier(radius: radius, glow: glow))
    }
}

// MARK: - Buttons

/// Primary call to action: the one place the brand accent is allowed to shout.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.dreamDisplay(16, .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                LinearGradient(
                    colors: [.dreamPrimary, .dreamAccent],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: .rect(cornerRadius: DreamMetric.controlRadius)
            )
            .shadow(color: Color.dreamPrimary.opacity(0.4), radius: 12, y: 6)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Quiet secondary action: transparent fill, soft outline, no accent color.
struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.dreamDisplay(16, .bold))
            .foregroundStyle(Color.dreamText.opacity(0.7))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.dreamText.opacity(0.05), in: .rect(cornerRadius: DreamMetric.controlRadius))
            .overlay(
                RoundedRectangle(cornerRadius: DreamMetric.controlRadius)
                    .stroke(Color.dreamText.opacity(0.12), lineWidth: 1.5)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
