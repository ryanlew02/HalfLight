//
//  ReminderScheduler.swift
//  HalfLight
//
//  Local notifications that nudge the dreamer to keep journaling:
//    1. Morning  — a daily prompt to capture last night's dream while it's fresh.
//    2. Inactivity — fires ~24h after the app was last used, rolling forward each
//       time the app is opened or a dream is logged.
//    3. Streak rescue — an evening warning, only when a live streak is about to
//       break (nothing journaled yet today).
//
//  `refresh` reconciles all three against the current state and is safe to call
//  often; it no-ops (and clears everything) when reminders are off or unauthorized.
//

import Foundation
import UserNotifications

@MainActor
final class ReminderScheduler {
    static let shared = ReminderScheduler()

    private let center = UNUserNotificationCenter.current()

    private enum ID {
        static let morning = "reminder.morning"
        static let inactivity = "reminder.inactivity"
        static let streak = "reminder.streak"
        static let all = [morning, inactivity, streak]
    }

    /// When the evening / inactivity reminders fire. The morning time is chosen by
    /// the dreamer and passed into `refresh`.
    private let streakHour = 21
    private let streakMinute = 30
    private let inactivityInterval: TimeInterval = 24 * 60 * 60

    private init() {}

    // MARK: - Authorization

    /// Ask the user for notification permission. Returns whether it's granted.
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    // MARK: - Reconcile

    /// Bring all reminders in line with the current state. Call on app launch /
    /// foreground, after logging a dream, and when the setting changes. Requests
    /// permission the first time reminders are enabled. Returns `false` only when
    /// reminders are enabled but permission is unavailable, so the caller can
    /// reflect that (e.g. switch the setting back off).
    @discardableResult
    func refresh(
        enabled: Bool,
        journaledToday: Bool,
        currentStreak: Int,
        morningHour: Int,
        morningMinute: Int
    ) async -> Bool {
        guard enabled else {
            cancelAll()
            return true
        }

        let status = await center.notificationSettings().authorizationStatus
        let authorized: Bool
        switch status {
        case .notDetermined: authorized = await requestAuthorization()
        case .authorized, .provisional, .ephemeral: authorized = true
        default: authorized = false
        }

        guard authorized else {
            cancelAll()
            return false
        }

        scheduleMorning(hour: morningHour, minute: morningMinute)
        scheduleInactivity()
        scheduleStreakRescue(journaledToday: journaledToday, currentStreak: currentStreak)
        return true
    }

    /// Remove every scheduled reminder (used when the setting is turned off).
    func cancelAll() {
        center.removePendingNotificationRequests(withIdentifiers: ID.all)
    }

    // MARK: - Individual reminders

    private func scheduleMorning(hour: Int, minute: Int) {
        var time = DateComponents()
        time.hour = hour
        time.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: time, repeats: true)
        add(
            ID.morning,
            title: "Catch your dream ☀️",
            body: "Write down last night's dream before it fades.",
            trigger: trigger
        )
    }

    private func scheduleInactivity() {
        center.removePendingNotificationRequests(withIdentifiers: [ID.inactivity])
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: inactivityInterval, repeats: false)
        add(
            ID.inactivity,
            title: "Your dream journal misses you",
            body: "It's been a day — log a dream to keep the habit going.",
            trigger: trigger
        )
    }

    private func scheduleStreakRescue(journaledToday: Bool, currentStreak: Int) {
        center.removePendingNotificationRequests(withIdentifiers: [ID.streak])
        // Only warn when there's a live streak that today hasn't secured yet.
        guard currentStreak >= 1, !journaledToday else { return }

        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: .now)
        components.hour = streakHour
        components.minute = streakMinute
        // If it's already past tonight's warning time, there's no point scheduling.
        guard let fireDate = calendar.date(from: components), fireDate > .now else { return }

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate),
            repeats: false
        )
        add(
            ID.streak,
            title: "Don't lose your \(currentStreak)-day streak 🔥",
            body: "Log tonight's dream before midnight to keep it alive.",
            trigger: trigger
        )
    }

    // MARK: - Helpers

    private func add(_ id: String, title: String, body: String, trigger: UNNotificationTrigger) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        // Re-adding with the same identifier replaces any existing copy.
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}
