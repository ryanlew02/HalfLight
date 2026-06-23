//
//  LucidLessonView.swift
//  HalfLight
//
//  The interactive, stepped flow for a single lucid lesson: hook + explanation,
//  an answer-and-learn quiz, a reflection prompt, a tiny challenge, and a
//  rewarding completion screen. A slim progress bar gives it a Duolingo-style feel.
//

import SwiftUI

struct LucidLessonView: View {
    let lesson: LucidLessonContent
    /// Called when the dreamer finishes the final step (awards XP / unlocks next).
    let onComplete: () -> Void

    @Environment(\.dismiss) private var dismiss

    private enum Step: Int, CaseIterable {
        case intro, quiz, reflection, challenge, complete
    }

    /// One answer choice, with its position shuffled so the correct option isn't
    /// always in the same slot.
    private struct QuizChoice: Identifiable {
        let id = UUID()
        let text: String
        let isCorrect: Bool
    }

    @State private var step: Step = .intro
    /// Index into `choices` of the option the dreamer tapped, or nil before answering.
    @State private var selectedAnswer: Int?
    @State private var reflectionText = ""
    /// The quiz options in their shuffled display order. Fixed for the life of this
    /// lesson view so the layout doesn't reshuffle mid-answer.
    @State private var choices: [QuizChoice]

    init(lesson: LucidLessonContent, onComplete: @escaping () -> Void) {
        self.lesson = lesson
        self.onComplete = onComplete
        _choices = State(initialValue: Self.makeChoices(for: lesson.quiz))
    }

    /// Build the answer choices with the correct one flagged, then shuffle them so
    /// the right answer lands in a random position.
    private static func makeChoices(for quiz: LucidQuiz) -> [QuizChoice] {
        quiz.options.enumerated()
            .map { QuizChoice(text: $0.element, isCorrect: $0.offset == quiz.answer) }
            .shuffled()
    }

    private var progress: Double {
        Double(step.rawValue + 1) / Double(Step.allCases.count)
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar

            ScrollView {
                content
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            bottomBar
        }
        .background { DreamBackground().ignoresSafeArea() }
    }

    // MARK: - Top bar (progress + close)

    private var topBar: some View {
        HStack(spacing: DreamMetric.md) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.dreamText.opacity(0.5))
            }
            .accessibilityLabel("Close lesson")

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.dreamText.opacity(0.1))
                    Capsule()
                        .fill(LinearGradient(
                            colors: [.dreamPrimary, .dreamAccent],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(width: max(8, geo.size.width * progress))
                }
            }
            .frame(height: 8)
            .animation(.easeInOut(duration: 0.3), value: progress)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Step content

    @ViewBuilder
    private var content: some View {
        switch step {
        case .intro: introStep
        case .quiz: quizStep
        case .reflection: reflectionStep
        case .challenge: challengeStep
        case .complete: completeStep
        }
    }

    private var introStep: some View {
        VStack(alignment: .leading, spacing: DreamMetric.lg) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [.dreamPrimary, .dreamAccent],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 64, height: 64)
                    .shadow(color: Color.dreamPrimary.opacity(0.5), radius: 12, y: 4)
                Image(systemName: lesson.icon)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
            }

            Text(lesson.title)
                .font(.dreamDisplay(26))
                .foregroundStyle(Color.dreamText)

            Text(lesson.hook)
                .font(.dreamSerif(18, italic: true))
                .foregroundStyle(Color.dreamPrimary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            Text(lesson.teach)
                .font(.dreamBody(16))
                .foregroundStyle(.secondary)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)

            if !lesson.didYouKnow.isEmpty {
                VStack(alignment: .leading, spacing: DreamMetric.sm) {
                    HStack(spacing: DreamMetric.sm) {
                        Image(systemName: "sparkle.magnifyingglass")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Did you know?")
                            .font(.dreamMono(11, .semibold))
                            .tracking(2)
                            .textCase(.uppercase)
                    }
                    .foregroundStyle(Color.dreamAccent)

                    Text(lesson.didYouKnow)
                        .font(.dreamBody(14))
                        .foregroundStyle(Color.dreamText.opacity(0.85))
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DreamMetric.lg)
                .background(Color.dreamAccent.opacity(0.08), in: .rect(cornerRadius: DreamMetric.cardRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: DreamMetric.cardRadius)
                        .stroke(Color.dreamAccent.opacity(0.25), lineWidth: 1)
                )
            }
        }
    }

    private var quizStep: some View {
        VStack(alignment: .leading, spacing: DreamMetric.lg) {
            stepEyebrow("Quick check")

            Text(lesson.quiz.question)
                .font(.dreamDisplay(20))
                .foregroundStyle(Color.dreamText)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: DreamMetric.md) {
                ForEach(Array(choices.enumerated()), id: \.element.id) { index, choice in
                    quizOption(index: index, choice: choice)
                }
            }

            if let selected = selectedAnswer {
                let correct = choices[selected].isCorrect
                HStack(alignment: .top, spacing: DreamMetric.sm) {
                    Image(systemName: correct ? "checkmark.circle.fill" : "info.circle.fill")
                    Text(lesson.quiz.why)
                        .font(.dreamBody(13, .medium))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(correct ? Color.dreamPrimary : Color.dreamText.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DreamMetric.md)
                .background(
                    (correct ? Color.dreamPrimary : Color.dreamText).opacity(0.1),
                    in: .rect(cornerRadius: DreamMetric.controlRadius)
                )
                .transition(.opacity)
            }
        }
    }

    private func quizOption(index: Int, choice: QuizChoice) -> some View {
        let answered = selectedAnswer != nil
        let isAnswer = choice.isCorrect
        let isChosen = index == selectedAnswer

        // Color logic: once answered, the correct option turns green; a wrong
        // chosen option turns red; the rest dim.
        let fill: Color
        let border: Color
        if !answered {
            fill = Color.dreamSurface
            border = Color.dreamText.opacity(0.12)
        } else if isAnswer {
            fill = Color.green.opacity(0.18)
            border = .green
        } else if isChosen {
            fill = Color.red.opacity(0.16)
            border = .red
        } else {
            fill = Color.dreamSurface.opacity(0.5)
            border = Color.dreamText.opacity(0.08)
        }

        return Button {
            guard selectedAnswer == nil else { return }
            SoundManager.shared.play(choice.isCorrect ? .correct : .wrong)
            withAnimation(.easeInOut(duration: 0.2)) { selectedAnswer = index }
        } label: {
            HStack(spacing: DreamMetric.md) {
                Text(choice.text)
                    .font(.dreamBody(15, .medium))
                    .foregroundStyle(Color.dreamText)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if answered, isAnswer {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else if answered, isChosen {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DreamMetric.lg)
            .background(fill, in: .rect(cornerRadius: DreamMetric.controlRadius))
            .overlay(
                RoundedRectangle(cornerRadius: DreamMetric.controlRadius)
                    .stroke(border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(answered)
    }

    private var reflectionStep: some View {
        VStack(alignment: .leading, spacing: DreamMetric.lg) {
            stepEyebrow("Reflect")

            Text(lesson.reflection)
                .font(.dreamDisplay(20))
                .foregroundStyle(Color.dreamText)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Just for you…", text: $reflectionText, axis: .vertical)
                .font(.dreamBody(16))
                .lineLimit(3...6)
                .padding(DreamMetric.lg)
                .background(Color.dreamSurface, in: .rect(cornerRadius: DreamMetric.controlRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: DreamMetric.controlRadius)
                        .stroke(Color.dreamText.opacity(0.12), lineWidth: 1)
                )

            Text("No right answers here — reflection is its own reward.")
                .font(.dreamBody(12))
                .foregroundStyle(.secondary)
        }
    }

    private var challengeStep: some View {
        VStack(alignment: .leading, spacing: DreamMetric.lg) {
            stepEyebrow("Tonight's challenge")

            HStack(alignment: .top, spacing: DreamMetric.md) {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.dreamPrimary)
                Text(lesson.challenge)
                    .font(.dreamBody(17, .medium))
                    .foregroundStyle(Color.dreamText)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DreamMetric.xl)
            .background(Color.dreamPrimary.opacity(0.1), in: .rect(cornerRadius: DreamMetric.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: DreamMetric.cardRadius)
                    .stroke(Color.dreamPrimary.opacity(0.3), lineWidth: 1)
            )

            Text("Small actions, done today, are how dreamers are made.")
                .font(.dreamBody(12))
                .foregroundStyle(.secondary)
        }
    }

    private var completeStep: some View {
        VStack(alignment: .center, spacing: DreamMetric.lg) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [.dreamPrimary, .dreamAccent],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 84, height: 84)
                    .shadow(color: Color.dreamPrimary.opacity(0.6), radius: 18)
                Image(systemName: "checkmark")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.white)
            }
            .padding(.top, DreamMetric.lg)

            Text("Lesson complete")
                .font(.dreamMono(12, .semibold))
                .tracking(2)
                .textCase(.uppercase)
                .foregroundStyle(Color.dreamAccent)

            Text(lesson.done)
                .font(.dreamSerif(20))
                .foregroundStyle(Color.dreamText)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            Text("+\(lesson.xp) XP")
                .font(.dreamDisplay(22, .bold))
                .foregroundStyle(Color.dreamPrimary)
                .padding(.horizontal, DreamMetric.lg)
                .padding(.vertical, DreamMetric.sm)
                .background(Color.dreamPrimary.opacity(0.12), in: .capsule)

            if !lesson.tip.isEmpty {
                HStack(alignment: .top, spacing: DreamMetric.sm) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(Color.dreamAccent)
                    Text(lesson.tip)
                        .font(.dreamBody(13, .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DreamMetric.md)
                .background(Color.dreamSurface, in: .rect(cornerRadius: DreamMetric.controlRadius))
                .padding(.top, DreamMetric.sm)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func stepEyebrow(_ text: String) -> some View {
        Text(text)
            .font(.dreamMono(11, .semibold))
            .tracking(2)
            .textCase(.uppercase)
            .foregroundStyle(Color.dreamAccent)
    }

    // MARK: - Bottom action

    private var bottomBar: some View {
        Button(action: advance) {
            Text(primaryLabel)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(LessonButtonStyle())
        .disabled(step == .quiz && selectedAnswer == nil)
        .opacity(step == .quiz && selectedAnswer == nil ? 0.5 : 1)
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

    private var primaryLabel: String {
        switch step {
        case .intro: "Begin quiz"
        case .quiz: selectedAnswer == nil ? "Choose an answer" : "Continue"
        case .reflection: "Continue"
        case .challenge: "I'm in"
        case .complete: "Finish"
        }
    }

    private func advance() {
        if step == .complete {
            // The reward popup that follows plays its own celebratory sound.
            onComplete()
            dismiss()
            return
        }
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        // The primary button's style plays the tap; just advance here.
        withAnimation(.easeInOut(duration: 0.25)) { step = next }
    }
}

/// A more tactile take on the primary button for the lesson flow: it presses in
/// deeper, its glow collapses as if pushed into the surface, and it springs back
/// with a little bounce — paired with a firm haptic for a satisfying "click".
private struct LessonButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .font(.dreamGrotesk(16, .bold))
            .foregroundStyle(Color.dreamOnPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(Color.dreamPrimary, in: .rect(cornerRadius: DreamMetric.controlRadius))
            // The halo tightens and dims on press, reading as the button sinking in.
            .shadow(
                color: Color.dreamPrimary.opacity(pressed ? 0.12 : 0.45),
                radius: pressed ? 3 : 14,
                y: pressed ? 1 : 7
            )
            .scaleEffect(pressed ? 0.93 : 1)
            .animation(.spring(response: 0.26, dampingFraction: 0.5), value: pressed)
            .onChange(of: pressed) { _, isPressed in
                if isPressed { SoundManager.shared.play(.tap) }
            }
    }
}

#Preview {
    LucidLessonView(lesson: LucidCurriculum.allLessons[0]) {}
}
