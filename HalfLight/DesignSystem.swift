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

/// The half-lit card: every screen hangs under the moonglow at the crown of the
/// sky, so surfaces behave like objects sitting in that light. The outline is
/// brightest along the top rim where it catches the glow and falls away into
/// shadow toward the bottom; a faint wash of the same light settles on the
/// card's upper face. Depth comes from that lighting, not a gray hairline.

/// The moonlit rim stroke. Pass `tint` to let an accent color carry the light
/// instead of the default moon tone (used for claimable-quest cards).
struct DreamCardRim: View {
    var radius: CGFloat
    var tint: Color? = nil

    var body: some View {
        let lit = tint ?? Color.dreamMoonRim
        let fade = tint ?? Color.dreamText
        RoundedRectangle(cornerRadius: radius)
            .strokeBorder(
                LinearGradient(
                    stops: [
                        .init(color: lit.opacity(tint == nil ? 0.55 : 0.7), location: 0),
                        .init(color: lit.opacity(tint == nil ? 0.16 : 0.4), location: 0.25),
                        .init(color: fade.opacity(tint == nil ? 0.07 : 0.28), location: 0.6),
                        .init(color: fade.opacity(tint == nil ? 0.05 : 0.22), location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                ),
                lineWidth: 1
            )
    }
}

/// The card fill: the flat surface tone with a whisper of moonlight settling
/// across its upper face, echoing the sky's top-anchored glow.
struct DreamCardFill: View {
    var radius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(Color.dreamSurface)
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: Color.dreamMoonRim.opacity(0.07), location: 0),
                                .init(color: .clear, location: 0.45),
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
            )
    }
}

/// A tiny four-point star, the same species as the backdrop's starfield —
/// perched on a hero card's rim like a star that came to rest there.
struct StarGlint: Shape {
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        let pull: CGFloat = 0.18 // how far the inward curves bow toward center
        var path = Path()
        path.move(to: CGPoint(x: c.x, y: c.y - r))
        path.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y),
                          control: CGPoint(x: c.x + r * pull, y: c.y - r * pull))
        path.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r),
                          control: CGPoint(x: c.x + r * pull, y: c.y + r * pull))
        path.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y),
                          control: CGPoint(x: c.x - r * pull, y: c.y + r * pull))
        path.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r),
                          control: CGPoint(x: c.x - r * pull, y: c.y - r * pull))
        path.closeSubpath()
        return path
    }
}

/// The glint dressed for the rim: moon-toned with a soft halo.
struct StarGlintView: View {
    var size: CGFloat = 11

    var body: some View {
        StarGlint()
            .fill(Color.dreamMoonRim)
            .frame(width: size, height: size)
            .shadow(color: Color.dreamMoonRim.opacity(0.7), radius: 4)
    }
}

struct DreamSurfaceModifier: ViewModifier {
    var radius: CGFloat = DreamMetric.cardRadius
    var glow: Color? = nil
    var starred: Bool = false

    func body(content: Content) -> some View {
        content
            .background {
                // Shadows hang off the flat background shape, not the finished
                // card: blurring a plain rounded rect is far cheaper than
                // re-rasterizing the whole subtree (text, gradients, rim) for
                // the blur, which is what stutters a gridful of cards. The
                // glow shadow only exists when a glow is asked for — a clear
                // 44pt blur is not guaranteed to be free.
                if let glow {
                    DreamCardFill(radius: radius)
                        .shadow(color: Color.dreamCardShadow.opacity(0.1), radius: 12, x: 0, y: 6)
                        .shadow(color: glow.opacity(0.22), radius: 44, x: 0, y: 6)
                } else {
                    DreamCardFill(radius: radius)
                        .shadow(color: Color.dreamCardShadow.opacity(0.1), radius: 12, x: 0, y: 6)
                }
            }
            .overlay(DreamCardRim(radius: radius))
            .overlay(alignment: .topTrailing) {
                if starred {
                    StarGlintView()
                        .offset(x: -28, y: -5.5)
                }
            }
    }
}

extension View {
    /// Apply the standard half-lit card surface. Pass `glow` to add a soft
    /// colored halo (used to make the current-level card feel lit from within);
    /// pass `starred: true` to perch a star glint on the top rim of hero cards.
    func dreamCard(
        radius: CGFloat = DreamMetric.cardRadius,
        glow: Color? = nil,
        starred: Bool = false
    ) -> some View {
        modifier(DreamSurfaceModifier(radius: radius, glow: glow, starred: starred))
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
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed { SoundManager.shared.play(.tap) }
            }
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
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed { SoundManager.shared.play(.tap) }
            }
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
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed { SoundManager.shared.play(.tap) }
            }
    }
}
