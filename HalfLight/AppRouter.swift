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

    /// Switch to the Progress tab and scroll to the weekly quests.
    func showQuests() {
        scrollToQuests = true
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            tab = .progress
        }
    }

    /// Present the reward animation for a just-claimed quest.
    func presentClaim(xp: Int, title: String) {
        withAnimation(.easeOut(duration: 0.3)) {
            claimReward = ClaimReward(xp: xp, title: title)
        }
    }

    func dismissClaim() {
        withAnimation(.easeOut(duration: 0.25)) {
            claimReward = nil
        }
    }
}
