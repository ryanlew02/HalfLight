//
//  LucidDreamView.swift
//  HalfLight
//
//  Lucid dreaming tools. Placeholder content for now.
//

import SwiftUI

struct LucidDreamView: View {
    private let techniques = [
        ("Reality Checks", "hand.raised.fill", "Throughout the day, ask yourself whether you're dreaming and test reality."),
        ("Dream Journaling", "book.fill", "Recording dreams sharpens recall and reveals recurring dream signs."),
        ("MILD", "brain.head.profile", "As you fall asleep, repeat the intention to recognize you're dreaming."),
        ("Wake Back to Bed", "bed.double.fill", "Wake after ~5 hours, stay up briefly, then return to sleep.")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    intro
                    ForEach(techniques, id: \.0) { technique in
                        techniqueCard(
                            title: technique.0,
                            icon: technique.1,
                            detail: technique.2
                        )
                    }
                }
                .padding(20)
            }
            .background { DreamBackground() }
            .navigationTitle("Lucid Dreams")
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "moon.stars.fill")
                .font(.largeTitle)
                .foregroundStyle(Color.dreamPrimary)
            Text("Become aware inside your dreams")
                .font(.title2.weight(.bold))
            Text("Practice these techniques to recognize when you're dreaming and take control. Guided tools are coming soon.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func techniqueCard(title: String, icon: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.dreamPrimary)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.dreamSurface, in: .rect(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.dreamText.opacity(0.08), lineWidth: 1)
        )
    }
}

#Preview("Light") {
    LucidDreamView()
}

#Preview("Dark") {
    LucidDreamView()
        .preferredColorScheme(.dark)
}
