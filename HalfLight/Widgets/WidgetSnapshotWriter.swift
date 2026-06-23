//
//  WidgetSnapshotWriter.swift
//  HalfLight
//
//  App-side bridge to the widgets: rebuilds the shared DreamSnapshot from the
//  live journal and nudges WidgetKit to redraw. Called from MainTabView whenever
//  the dream library or journaled days change. App target only.
//

import Foundation
import WidgetKit

@MainActor
enum WidgetSnapshotWriter {
    /// Recompute the snapshot from current state and, when it actually changed,
    /// persist it and refresh every widget timeline. Cheap and idempotent.
    static func update(dreams: [Dream], journaledDays: Set<Date>) {
        let streak = Streak.from(journaledDays: journaledDays)
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
        let latest = dreams.max { $0.date < $1.date }

        let snapshot = DreamSnapshot(
            currentStreak: streak.current,
            longestStreak: streak.longest,
            totalDreams: dreams.count,
            lucidCount: dreams.filter(\.isLucid).count,
            weekCount: dreams.filter { $0.date >= weekAgo }.count,
            lastDreamTitle: latest?.title,
            lastDreamMood: latest?.mood.rawValue,
            lastDreamMoodSymbol: latest?.mood.symbol,
            lastDreamMoodColor: latest.map { $0.mood.tintHex },
            lastDreamDate: latest?.date
        )

        guard snapshot != DreamSnapshot.load() else { return }
        snapshot.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
