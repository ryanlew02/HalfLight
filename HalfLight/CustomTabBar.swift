//
//  CustomTabBar.swift
//  HalfLight
//
//  Bottom navigation bar with a raised center "+" for adding a dream.
//

import SwiftUI

struct CustomTabBar: View {
    @Binding var selection: AppTab
    let onAdd: () -> Void

    /// Incremented on each "+" tap to drive the add animation.
    @State private var addTaps = 0

    /// Animatable state for the expanding ripple ring behind the "+".
    private struct Ripple {
        var scale: CGFloat = 1
        var opacity: Double = 0
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            tabButton(.home)
            tabButton(.lucid)
            addButton
            tabButton(.journal)
            tabButton(.stats)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 4)
        .background(
            Rectangle()
                .fill(Color.dreamBase)
                .ignoresSafeArea(edges: .bottom)
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.dreamText.opacity(0.08))
                .frame(height: 1)
        }
    }

    private func tabButton(_ tab: AppTab) -> some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                selection = tab
            }
        } label: {
            Image(systemName: tab.icon)
                .font(.system(size: 22))
                .foregroundStyle(selection == tab ? Color.dreamPrimary : .secondary)
                .scaleEffect(selection == tab ? 1.1 : 1.0)
                .symbolEffect(.bounce, value: selection == tab)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
    }

    private var addButton: some View {
        Button {
            // Play the tap animation, then open the sheet so it's visible first.
            addTaps += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                onAdd()
            }
        } label: {
            ZStack {
                // Soft glow that swells out of the button and fades — anchored
                // to the "+", so it reads as light radiating rather than a
                // detached ring.
                Circle()
                    .fill(Color.dreamPrimary)
                    .frame(width: 60, height: 60)
                    .blur(radius: 8)
                    .keyframeAnimator(initialValue: Ripple(), trigger: addTaps) { content, value in
                        content
                            .scaleEffect(value.scale)
                            .opacity(value.opacity)
                    } keyframes: { _ in
                        KeyframeTrack(\.scale) {
                            CubicKeyframe(1.0, duration: 0.01)
                            CubicKeyframe(1.7, duration: 0.5)
                        }
                        KeyframeTrack(\.opacity) {
                            CubicKeyframe(0.5, duration: 0.01)
                            CubicKeyframe(0.0, duration: 0.5)
                        }
                    }

                Image(systemName: "plus")
                    .font(.system(size: 27, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 60, height: 60)
                    .background(
                        LinearGradient(
                            colors: [.dreamPrimary, .dreamAccent],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: .circle
                    )
                    .shadow(color: Color.dreamPrimary.opacity(0.5), radius: 8, y: 4)
                    // Springy pop on tap.
                    .keyframeAnimator(initialValue: 1.0, trigger: addTaps) { content, scale in
                        content.scaleEffect(scale)
                    } keyframes: { _ in
                        KeyframeTrack {
                            SpringKeyframe(1.25, duration: 0.18, spring: .bouncy)
                            SpringKeyframe(1.0, duration: 0.25, spring: .bouncy)
                        }
                    }
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        // Constrain the layout height so the larger circle overflows upward
        // instead of inflating the whole bar.
        .frame(height: 38)
        .offset(y: 2)
        .accessibilityLabel("Add Dream")
        .sensoryFeedback(trigger: addTaps) { _, _ in .impact(flexibility: .soft) }
    }
}
