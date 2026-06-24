//
//  LucidDreamView.swift
//  HalfLight
//
//  Lucid dreaming training as a Duolingo-style lesson map. The path is built from
//  `LucidCurriculum` and unlocked one lesson at a time via `LucidProgress`. Each
//  section is a header banner followed by a winding trail of lesson nodes; tapping
//  an unlocked node opens the interactive lesson flow.
//

import SwiftUI

struct LucidDreamView: View {
    @Environment(AppRouter.self) private var router

    private let sections = LucidCurriculum.sections

    /// Mirrors the completed-lesson count; reading it here re-renders the path the
    /// instant a lesson is finished (the same key `LucidProgress` writes).
    @AppStorage("lucidSectionsCompleted") private var completedCount = 0

    /// The lesson currently open in the full-screen flow.
    @State private var activeLesson: LucidLessonContent?

    private var currentID: String? { LucidProgress.currentLessonID() }

    var body: some View {
        // Reading `completedCount` here ties the path's redraw to the same key
        // `LucidProgress.complete` writes, so finishing a lesson immediately
        // re-evaluates every node's locked/current/completed status.
        let _ = completedCount

        return NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    Text("Lucid Path")
                        .font(.dreamTitle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)

                    ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                        LucidSectionHeader(
                            section: section,
                            isUnlocked: section.lessons.contains { LucidProgress.status(for: $0.id) != .locked },
                            isActive: section.lessons.contains { $0.id == currentID },
                            showConnector: index > 0
                        )
                        .padding(.horizontal, 20)
                        .padding(.top, index == 0 ? 24 : 0)

                        LucidLessonMap(
                            lessons: section.lessons,
                            status: { LucidProgress.status(for: $0.id) },
                            onTap: open
                        )
                    }
                }
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
            .tabBarClearance()
            .background { DreamBackground().ignoresSafeArea() }
            .toolbar(.hidden, for: .navigationBar)
            .fullScreenCover(item: $activeLesson) { lesson in
                LucidLessonView(lesson: lesson) {
                    let isNew = LucidProgress.complete(lesson.id)
                    completedCount = LucidProgress.completedIDs().count
                    // Celebrate only genuinely-earned XP, once the lesson sheet
                    // has dismissed so the full-screen reward isn't covered by it.
                    if isNew {
                        router.presentClaim(
                            xp: lesson.xp,
                            title: lesson.title,
                            headline: "Lesson Complete"
                        )
                    }
                }
            }
        }
    }

    /// Open a lesson unless it's still locked.
    private func open(_ lesson: LucidLessonContent) {
        guard LucidProgress.status(for: lesson.id) != .locked else { return }
        activeLesson = lesson
    }
}

/// Method header followed by a dotted line that runs across the screen to mark
/// the break between sections of the path.
private struct LucidSectionHeader: View {
    let section: LucidSectionContent
    /// The badge lights up once any lesson in the section is reachable.
    let isUnlocked: Bool
    /// The section you're currently working through glows.
    let isActive: Bool
    var showConnector: Bool = false

    @State private var glow = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(badgeFill)
                    .frame(width: 42, height: 42)
                    .shadow(color: shadowColor, radius: shadowRadius)
                Image(systemName: isUnlocked ? section.icon : "lock.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isUnlocked ? .white : .secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(localized(section.title))
                    .font(.dreamCardTitle)
                    .foregroundStyle(isUnlocked ? Color.dreamText : .secondary)
                Text(localized(section.subtitle))
                    .font(.dreamCaption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.dreamSurface)
                .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
        }
        .background {
            if showConnector {
                VerticalLine()
                    .stroke(
                        Color.dreamText.opacity(0.12),
                        style: StrokeStyle(lineWidth: 9, lineCap: .round, dash: [1, 16])
                    )
                    .frame(width: 9)
                    .padding(.top, -34)
                    .padding(.bottom, -70)
            }
        }
        .onAppear {
            guard isActive else { return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                glow = true
            }
        }
    }

    private var shadowColor: Color {
        guard isActive else { return Color.dreamPrimary.opacity(0) }
        return Color.dreamPrimary.opacity(glow ? 0.85 : 0.4)
    }

    private var shadowRadius: CGFloat { glow ? 16 : 8 }

    private var badgeFill: AnyShapeStyle {
        isUnlocked
            ? AnyShapeStyle(LinearGradient(
                colors: [.dreamPrimary, .dreamAccent],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
            : AnyShapeStyle(Color.dreamSurface)
    }
}

/// A vertical line shape used for the dotted connector that links sections.
private struct VerticalLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}

/// The winding path of lesson nodes for one section, laid out in a fixed-height
/// canvas so the connecting trail can be drawn between exact node centers.
private struct LucidLessonMap: View {
    let lessons: [LucidLessonContent]
    let status: (LucidLessonContent) -> LucidLessonStatus
    let onTap: (LucidLessonContent) -> Void

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
                    LessonNode(lesson: lesson, status: status(lesson)) {
                        onTap(lesson)
                    }
                    .position(points[index])
                    .id(lesson.id)
                }
            }
            .frame(width: geo.size.width, height: contentHeight)
        }
        .frame(height: contentHeight)
    }

    private func trailColor(below lesson: LucidLessonContent) -> Color {
        status(lesson) == .completed
            ? Color.dreamPrimary.opacity(0.55)
            : Color.dreamText.opacity(0.12)
    }
}

/// Callout shown when a lesson node is tapped: the lesson name, the XP it awards,
/// and a Start button that begins the lesson (disabled while the lesson is locked).
private struct LessonInfoCallout: View {
    let lesson: LucidLessonContent
    let status: LucidLessonStatus
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localized(lesson.title))
                .font(.headline.weight(.bold))
                .foregroundStyle(Color.dreamText)

            if status == .locked {
                Text("Complete earlier lessons to unlock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button(action: onStart) {
                HStack(spacing: 8) {
                    Text(status == .completed ? "Review" : "Start")
                        .font(.subheadline.weight(.bold))

                    Spacer(minLength: 0)

                    Text("+\(lesson.xp) XP")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(.vertical, 10)
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity)
                .background(
                    Capsule().fill(LinearGradient(
                        colors: [.dreamPrimary, .dreamAccent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                )
            }
            .buttonStyle(.plain)
            .disabled(status == .locked)
            .opacity(status == .locked ? 0.4 : 1)
        }
        .padding(16)
        .frame(maxWidth: 260, alignment: .leading)
    }
}

private struct LessonNode: View {
    let lesson: LucidLessonContent
    let status: LucidLessonStatus
    /// Called when the dreamer taps Start in the callout to begin the lesson.
    let onStart: () -> Void

    @State private var pulse = false
    /// Tapping a node reveals a callout with the lesson name, XP, and a Start button.
    @State private var showInfo = false

    private var size: CGFloat { status == .current ? 74 : 72 }

    var body: some View {
        Button {
            showInfo = true
        } label: {
            ZStack {
                if status == .current {
                    Circle()
                        .stroke(Color.dreamPrimary.opacity(0.25), lineWidth: 4)
                        .frame(width: size + 12, height: size + 12)
                        .scaleEffect(pulse ? 1.08 : 0.94)
                        .opacity(pulse ? 0.15 : 0.4)
                }
                Circle()
                    .fill(fill)
                    .frame(width: size, height: size)
                    .overlay(Circle().stroke(ringColor, lineWidth: 4))
                    .shadow(color: shadowColor, radius: 8, y: 4)

                Image(systemName: status == .locked ? "lock.fill" : lesson.icon)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(iconColor)

                if status == .completed {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white, Color.dreamPrimary)
                        .background(Circle().fill(Color.dreamPrimary).frame(width: 20, height: 20))
                        .offset(x: size / 2 - 6, y: -size / 2 + 6)
                }
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showInfo, arrowEdge: .top) {
            LessonInfoCallout(lesson: lesson, status: status) {
                showInfo = false
                onStart()
            }
            .presentationCompactAdaptation(.popover)
        }
        .onAppear {
            guard status == .current else { return }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    private var fill: AnyShapeStyle {
        switch status {
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
        switch status {
        case .completed: Color.white.opacity(0.5)
        case .current: Color.white.opacity(0.8)
        case .locked: Color.dreamText.opacity(0.1)
        }
    }

    private var iconColor: Color {
        status == .locked ? .secondary : .white
    }

    private var shadowColor: Color {
        status == .locked
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
