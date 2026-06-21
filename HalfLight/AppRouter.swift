//
//  AppRouter.swift
//  HalfLight
//
//  App-wide navigation state shared through the environment: the selected tab and
//  one-shot intents like "jump to the quests on the Progress screen", so one screen
//  can drive navigation that another screen owns.
//

import SwiftUI

/// A celebration shown in the full-screen claim animation: either an XP payout or
/// a level-up (which reveals the dreamer's new rank).
struct ClaimReward: Identifiable, Equatable {
    enum Kind: Equatable { case xp, levelUp }

    let id = UUID()
    var kind: Kind = .xp
    /// XP rewards: the amount earned. Unused (0) for level-ups.
    var xp: Int = 0
    /// The body line — the XP source for `.xp`, the rank name for `.levelUp`.
    let title: String
    /// The small uppercase eyebrow above the readout, e.g. "Quest Complete",
    /// "Achievement Unlocked", or "Level Up".
    var headline: String = "Reward"
    /// Level-up rewards: the level just reached. Unused (0) for XP rewards.
    var level: Int = 0
}

@MainActor
@Observable
final class AppRouter {
    /// The currently selected bottom tab.
    var tab: AppTab = .lucid

    /// Set when the Profile screen should push the Progress screen (e.g. from the
    /// Home quests shortcut). Consumed (and reset) by the Profile screen.
    var openProgress = false

    /// Set when the Progress screen should scroll to the weekly quests once shown.
    /// Consumed (and reset) by the Progress screen.
    var scrollToQuests = false

    /// Non-nil while the full-screen XP claim animation is showing.
    var claimReward: ClaimReward?

    /// Rewards waiting their turn behind the one currently on screen, so several
    /// celebrations (a logged dream plus the achievements it unlocked, say) play
    /// back-to-back instead of clobbering one another.
    private var claimQueue: [ClaimReward] = []

    /// Open the Progress screen (now under Profile) and scroll to the weekly quests.
    func showQuests() {
        openProgress = true
        scrollToQuests = true
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            tab = .profile
        }
    }

    /// Present the full-screen reward animation for any XP the dreamer just
    /// earned — a claimed quest, a finished lesson, a logged dream, and so on.
    func presentClaim(xp: Int, title: String, headline: String = "Quest Complete") {
        enqueue(ClaimReward(xp: xp, title: title, headline: headline))
    }

    /// Celebrate reaching a new level, revealing the dreamer's rank at that level.
    func presentLevelUp(level: Int, rank: String) {
        enqueue(ClaimReward(kind: .levelUp, title: rank, headline: "Level Up", level: level))
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
