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

    // Redesign radii (editorial / celestial system).
    /// Hero card & large feature tiles.
    static let heroRadius: CGFloat = 26
    /// The full-width capture CTA.
    static let ctaRadius: CGFloat = 20
    /// Smaller inset tiles (e.g. the week tracker).
    static let tileRadius: CGFloat = 18
    /// Small pills / chips.
    static let pillRadius: CGFloat = 14
}

// MARK: - Typography

extension Font {
    /// Display face — Instrument Serif. Used for titles, dream titles, greetings
    /// and big stat numbers. The serif carries the emphasis, so `weight` only
    /// nudges the system fallback; the bundled face is regular/italic.
    static func dreamDisplay(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        dreamSerif(size)
    }

    /// Body face — Space Grotesk. Running copy, buttons, supporting text.
    static func dreamBody(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        dreamGrotesk(size, weight)
    }

    // MARK: Semantic type ramp
    //
    // Named roles built on the three faces. Prefer these over the raw
    // `dreamSerif/Grotesk/Mono(_:)` helpers so the hierarchy stays consistent
    // across screens — one place to tune, no magic numbers drifting per-view.

    /// Top-of-screen page title (e.g. "Progress", "Journal"). Serif.
    static let dreamTitle = dreamSerif(26)
    /// A large hero title — greetings, dream titles in the hero card. Serif.
    static let dreamLargeTitle = dreamSerif(30)
    /// Section / card header sitting above grouped content. Serif.
    static let dreamSectionHeader = dreamSerif(20)
    /// A card's own title (the headline inside a surface). Serif, NOT bold.
    static let dreamCardTitle = dreamSerif(19)
    /// A compact card title, used in dense rows. Serif.
    static let dreamRowTitle = dreamSerif(16)
    /// Primary running body copy inside cards and detail screens. Grotesk.
    static let dreamBodyText = dreamGrotesk(15)
    /// Secondary supporting copy — the line beneath a title. Grotesk.
    static let dreamSubtext = dreamGrotesk(13)
    /// Small metadata / counts / pill labels. Mono.
    static let dreamCaption = dreamMono(12, .medium)
    /// Tiny mono eyebrow label (paired with `.dreamEyebrow()` for tracking + case).
    static let dreamEyebrow = dreamMono(10, .medium)
}

extension View {
    /// Comfortable line spacing for multi-line body copy. Single-line labels are
    /// unaffected, so this is safe to apply broadly to running text.
    func dreamBodyLineSpacing() -> some View {
        self.lineSpacing(4)
    }

    /// The signature mono eyebrow treatment: uppercased, letter-spaced, tinted.
    /// Apply to a `Text` already set in `.dreamEyebrow` (or any mono font).
    func dreamEyebrow(tracking: CGFloat = 1.6) -> some View {
        self.textCase(.uppercase)
            .tracking(tracking)
    }
}

// MARK: - Elevated surface

/// The card treatment for the editorial / celestial system: a flat filled
/// surface with a hairline inset stroke and only a whisper of ambient shadow —
/// depth comes from the inset edge, not a drop-shadow bloom. `glow` keeps a soft
/// colored halo available for elements that should feel lit from within.
struct DreamSurfaceModifier: ViewModifier {
    var radius: CGFloat = DreamMetric.cardRadius
    var glow: Color? = nil

    func body(content: Content) -> some View {
        content
            .background(Color.dreamSurface, in: .rect(cornerRadius: radius))
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(Color.dreamText.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.05), radius: 12, x: 0, y: 6)
            .shadow(color: (glow ?? .clear).opacity(glow == nil ? 0 : 0.22), radius: 44, x: 0, y: 6)
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

/// Primary call to action: a solid `dreamPrimary` fill with Space Grotesk label.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.dreamGrotesk(15, .semibold))
            .foregroundStyle(Color.dreamOnPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Color.dreamPrimary, in: .rect(cornerRadius: DreamMetric.controlRadius))
            .opacity(configuration.isPressed ? 0.9 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Quiet secondary action: transparent fill, hairline outline, no accent color.
struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.dreamGrotesk(15, .semibold))
            .foregroundStyle(Color.dreamText.opacity(0.7))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Color.dreamText.opacity(0.04), in: .rect(cornerRadius: DreamMetric.controlRadius))
            .overlay(
                RoundedRectangle(cornerRadius: DreamMetric.controlRadius)
                    .strokeBorder(Color.dreamText.opacity(0.12), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// A whole-tile press affordance: subtle scale + fade, no chrome of its own.
/// Used to make large cards (capture CTA, random-dream tile) feel tappable.
struct PressableTileStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.92 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
