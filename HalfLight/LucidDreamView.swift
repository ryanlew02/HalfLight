//
//  LucidDreamView.swift
//  HalfLight
//
//  Lucid dreaming training presented as a Duolingo-style lesson map. The path is
//  split into sections, one per lucid-dreaming method. Each section has its own
//  header banner followed by a winding trail of lesson nodes. You begin in
//  Foundations at the top and work downward, unlocking each method in turn.
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
    let xp: Int
}

/// A group of lessons belonging to a single lucid-dreaming method.
struct LucidSection: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let icon: String
    let lessons: [LucidLesson]
}

struct LucidDreamView: View {
    // Sections are ordered top-to-bottom: you complete Foundations before the
    // method sections unlock beneath it.
    private let sections: [LucidSection] = [
        LucidSection(
            title: "Foundations",
            subtitle: "The awareness habits every method relies on",
            icon: "moon.stars.fill",
            lessons: [
                LucidLesson(title: "What Is Lucid Dreaming?", icon: "sparkles", status: .current, xp: 10),
                LucidLesson(title: "Dream Recall Basics", icon: "book.fill", status: .locked, xp: 15),
                LucidLesson(title: "Reality Checks", icon: "hand.raised.fill", status: .locked, xp: 15)
            ]
        ),
        LucidSection(
            title: "MILD",
            subtitle: "Mnemonic Induction of Lucid Dreams",
            icon: "brain.head.profile",
            lessons: [
                LucidLesson(title: "What MILD Means", icon: "brain.head.profile", status: .locked, xp: 20),
                LucidLesson(title: "Setting a Lucid Intention", icon: "target", status: .locked, xp: 20),
                LucidLesson(title: "Visualizing the Dream Moment", icon: "eye.fill", status: .locked, xp: 25)
            ]
        ),
        LucidSection(
            title: "WBTB",
            subtitle: "Wake Back to Bed",
            icon: "bed.double.fill",
            lessons: [
                LucidLesson(title: "What Is Wake Back to Bed?", icon: "bed.double.fill", status: .locked, xp: 25),
                LucidLesson(title: "Finding the Right Wake Window", icon: "clock.fill", status: .locked, xp: 30),
                LucidLesson(title: "Combining WBTB With MILD", icon: "link", status: .locked, xp: 35)
            ]
        ),
        LucidSection(
            title: "WILD",
            subtitle: "Wake Initiated Lucid Dreams",
            icon: "sparkles",
            lessons: [
                LucidLesson(title: "What Is WILD?", icon: "sparkles", status: .locked, xp: 35),
                LucidLesson(title: "Staying Calm During Sleep Transition", icon: "wind", status: .locked, xp: 40),
                LucidLesson(title: "Entering the Dream Gently", icon: "cloud.moon.fill", status: .locked, xp: 45)
            ]
        )
    ]

    // The first section is active (glows); the rest read as locked.
    private var activeSectionID: LucidSection.ID? {
        sections.first?.id
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                        LucidSectionHeader(
                            section: section,
                            isActive: section.id == activeSectionID,
                            // Every section but the first gets a dotted line behind
                            // its header that continues the path up from the section above.
                            showConnector: index > 0
                        )
                        .padding(.horizontal, 20)
                        // The first section needs breathing room up top; later
                        // sections rely on the map pad above so the header sits
                        // centered between the nodes above and below it.
                        .padding(.top, index == 0 ? 24 : 0)

                        LucidLessonMap(lessons: section.lessons)
                    }
                }
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
            .tabBarClearance()
            .background { DreamBackground().ignoresSafeArea() }
            .navigationTitle("Lucid Path")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// Method header followed by a dotted line that runs across the screen to mark
/// the break between sections of the path.
private struct LucidSectionHeader: View {
    let section: LucidSection
    /// The section you're currently on glows; everything else reads as locked.
    let isActive: Bool
    /// Draws the vertical dotted connector behind the header, bridging the path
    /// from the section above. Off for the very first section.
    var showConnector: Bool = false

    @State private var glow = false

    private var isUnlocked: Bool { isActive }

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
                Text(section.title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(isUnlocked ? Color.dreamText : .secondary)
                Text(section.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        // Opaque card sits in front of the connector, hiding the line where it
        // crosses the header so it reads as passing behind the card.
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.dreamSurface)
                .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
        }
        .background {
            if showConnector {
                // Negative vertical padding stretches the line past the card so it
                // reaches the node above (top stops at its bottom edge, ~34pt up,
                // since that node draws in front) and the first node below (70pt).
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

    private var shadowRadius: CGFloat {
        glow ? 16 : 8
    }

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

/// Callout shown when a lesson node is tapped: the lesson name and its XP reward.
private struct LessonInfoCallout: View {
    let lesson: LucidLesson

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(lesson.title)
                .font(.headline.weight(.bold))
                .foregroundStyle(Color.dreamText)

            if lesson.status == .locked {
                Text("Complete earlier lessons to unlock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                // Begin the lesson.
            } label: {
                HStack(spacing: 8) {
                    Text("Start")
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
            .disabled(lesson.status == .locked)
            .opacity(lesson.status == .locked ? 0.4 : 1)
        }
        .padding(16)
        .frame(maxWidth: 260, alignment: .leading)
    }
}

private struct LessonNode: View {
    let lesson: LucidLesson

    @State private var pulse = false
    /// Tapping a node reveals a callout with the lesson name and its XP reward.
    @State private var showInfo = false

    private var size: CGFloat { lesson.status == .current ? 74 : 72 }

    var body: some View {
        Button {
            showInfo = true
        } label: {
            ZStack {
                if lesson.status == .current {
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

                Image(systemName: lesson.status == .locked ? "lock.fill" : lesson.icon)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(iconColor)
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showInfo, arrowEdge: .top) {
            LessonInfoCallout(lesson: lesson)
                .presentationCompactAdaptation(.popover)
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
