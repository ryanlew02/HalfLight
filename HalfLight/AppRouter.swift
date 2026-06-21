//
//  AppRouter.swift
//  HalfLight
//
//  App-wide navigation state shared through the environment: the selected tab and
//  one-shot intents like "jump to the quests on the Progress tab", so one screen
//  can drive navigation that another screen owns.
//

import SwiftUI

/// The XP payout being celebrated in the full-screen claim animation.
struct ClaimReward: Identifiable, Equatable {
    let id = UUID()
    let xp: Int
    let title: String
    /// The small uppercase eyebrow above the XP, e.g. "Quest Complete" or
    /// "Lesson Complete" — names what just earned the dreamer this XP.
    var headline: String = "Reward"
}

@MainActor
@Observable
final class AppRouter {
    /// The currently selected bottom tab.
    var tab: AppTab = .lucid

    /// Set when the Progress tab should scroll to the weekly quests once shown.
    /// Consumed (and reset) by the Progress screen.
    var scrollToQuests = false

    /// Non-nil while the full-screen XP claim animation is showing.
    var claimReward: ClaimReward?

    /// Rewards waiting their turn behind the one currently on screen, so several
    /// celebrations (a logged dream plus the achievements it unlocked, say) play
    /// back-to-back instead of clobbering one another.
    private var claimQueue: [ClaimReward] = []

    /// Switch to the Progress tab and scroll to the weekly quests.
    func showQuests() {
        scrollToQuests = true
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            tab = .progress
        }
    }

    /// Present the full-screen reward animation for any XP the dreamer just
    /// earned — a claimed quest, a finished lesson, a logged dream, and so on.
    func presentClaim(xp: Int, title: String, headline: String = "Quest Complete") {
        enqueue(ClaimReward(xp: xp, title: title, headline: headline))
    }

    /// Celebrate each freshly-unlocked achievement, one popup after another.
    func presentAchievements(_ achievements: [Achievement]) {
        for achievement in achievements {
            enqueue(ClaimReward(
                xp: achievement.xp,
                title: achievement.title,
                headline: "Achievement Unlocked"
            ))
        }
    }

    /// Show a reward now if the stage is clear, otherwise line it up to play next.
    private func enqueue(_ reward: ClaimReward) {
        guard claimReward != nil else {
            withAnimation(.easeOut(duration: 0.3)) { claimReward = reward }
            return
        }
        claimQueue.append(reward)
    }

    func dismissClaim() {
        withAnimation(.easeOut(duration: 0.25)) {
            claimReward = nil
        }
        guard !claimQueue.isEmpty else { return }
        let next = claimQueue.removeFirst()
        // Let the current celebration fade out before the next springs in.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            withAnimation(.easeOut(duration: 0.3)) { claimReward = next }
        }
    }
}
