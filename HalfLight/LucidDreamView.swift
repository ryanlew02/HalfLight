//
//  LucidDreamView.swift
//  HalfLight
//
//  Lucid dreaming training presented as a Duolingo-style lesson map: a winding
//  path of circular nodes that climbs up the screen. You begin at the bottom
//  and progress upward as lessons are completed.
//

import SwiftUI

enum LessonStatus {
    case completed
    case current
    case locked
}

struct LucidLesson: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let status: LessonStatus
}

struct LucidDreamView: View {
    // Index 0 is the first lesson and sits at the top of the path; the list
    // descends from there.
    private let lessons: [LucidLesson] = [
        LucidLesson(title: "Reality Checks", icon: "hand.raised.fill", status: .completed),
        LucidLesson(title: "Dream Journaling", icon: "book.fill", status: .completed),
        LucidLesson(title: "Dream Signs", icon: "eye.fill", status: .current),
        LucidLesson(title: "MILD", icon: "brain.head.profile", status: .locked),
        LucidLesson(title: "Wake Back to Bed", icon: "bed.double.fill", status: .locked),
        LucidLesson(title: "WILD", icon: "sparkles", status: .locked),
        LucidLesson(title: "Stabilizing", icon: "hand.tap.fill", status: .locked)
    ]

    private var currentLessonID: LucidLesson.ID? {
        lessons.first { $0.status == .current }?.id
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        intro
                            .padding(.horizontal, 20)
                            .padding(.bottom, 8)
                        LucidLessonMap(lessons: lessons)
                    }
                }
                .onAppear {
                    guard let currentLessonID else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation { proxy.scrollTo(currentLessonID, anchor: .center) }
                    }
                }
            }
            .background { DreamBackground() }
            .navigationTitle("Lucid Path")
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "moon.stars.fill")
                .font(.largeTitle)
                .foregroundStyle(Color.dreamPrimary)
            Text("Your path to lucidity")
                .font(.title2.weight(.bold))
            Text("Work your way down the path. Each lesson builds the awareness you need to recognize when you're dreaming.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The winding path of lesson nodes, laid out in a fixed-height canvas so the
/// connecting trail can be drawn between exact node centers.
private struct LucidLessonMap: View {
    let lessons: [LucidLesson]

    private let vSpacing: CGFloat = 132
    private let amplitude: CGFloat = 72
    private let topPad: CGFloat = 70
    private let bottomPad: CGFloat = 70

    private var contentHeight: CGFloat {
        CGFloat(max(lessons.count - 1, 0)) * vSpacing + topPad + bottomPad
    }

    private func positions(width: CGFloat) -> [CGPoint] {
        lessons.indices.map { i in
            let x = width / 2 + amplitude * sin(Double(i) * .pi / 2)
            let y = topPad + CGFloat(i) * vSpacing
            return CGPoint(x: x, y: y)
        }
    }

    var body: some View {
        GeometryReader { geo in
            let points = positions(width: geo.size.width)
            ZStack {
                // Connecting trail, drawn segment-by-segment so completed
                // stretches read brighter than the locked road ahead.
                ForEach(0..<max(lessons.count - 1, 0), id: \.self) { i in
                    Path { path in
                        path.move(to: points[i])
                        path.addLine(to: points[i + 1])
                    }
                    .stroke(
                        trailColor(below: lessons[i]),
                        style: StrokeStyle(lineWidth: 9, lineCap: .round, dash: [1, 16])
                    )
                }

                ForEach(Array(lessons.enumerated()), id: \.element.id) { index, lesson in
                    LessonNode(lesson: lesson)
                        .position(points[index])
                        .id(lesson.id)
                }
            }
            .frame(width: geo.size.width, height: contentHeight)
        }
        .frame(height: contentHeight)
    }

    private func trailColor(below lesson: LucidLesson) -> Color {
        lesson.status == .completed
            ? Color.dreamPrimary.opacity(0.55)
            : Color.dreamText.opacity(0.12)
    }
}

private struct LessonNode: View {
    let lesson: LucidLesson

    @State private var pulse = false

    private var size: CGFloat { lesson.status == .current ? 80 : 72 }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                if lesson.status == .current {
                    Circle()
                        .stroke(Color.dreamPrimary.opacity(0.35), lineWidth: 6)
                        .frame(width: size + 18, height: size + 18)
                        .scaleEffect(pulse ? 1.12 : 0.92)
                        .opacity(pulse ? 0.2 : 0.6)
                }

                Circle()
                    .fill(fill)
                    .frame(width: size, height: size)
                    .overlay(Circle().stroke(ringColor, lineWidth: 4))
                    .shadow(color: shadowColor, radius: 8, y: 4)

                Image(systemName: lesson.status == .locked ? "lock.fill" : lesson.icon)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(iconColor)
            }

            Text(lesson.title)
                .font(.caption.weight(.medium))
                .foregroundStyle(lesson.status == .locked ? .secondary : Color.dreamText)
        }
        .onAppear {
            guard lesson.status == .current else { return }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    private var fill: AnyShapeStyle {
        switch lesson.status {
        case .completed, .current:
            AnyShapeStyle(LinearGradient(
                colors: [.dreamPrimary, .dreamAccent],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
        case .locked:
            AnyShapeStyle(Color.dreamSurface)
        }
    }

    private var ringColor: Color {
        switch lesson.status {
        case .completed: Color.white.opacity(0.5)
        case .current: Color.white.opacity(0.8)
        case .locked: Color.dreamText.opacity(0.1)
        }
    }

    private var iconColor: Color {
        lesson.status == .locked ? .secondary : .white
    }

    private var shadowColor: Color {
        lesson.status == .locked
            ? .black.opacity(0.1)
            : Color.dreamPrimary.opacity(0.45)
    }
}

#Preview("Light") {
    LucidDreamView()
}

#Preview("Dark") {
    LucidDreamView()
        .preferredColorScheme(.dark)
}
