//
//  DreamProvider.swift
//  HalfLightWidgets
//
//  Feeds the dream widgets from the shared App Group snapshot. The app refreshes
//  WidgetKit on every change (WidgetSnapshotWriter), so the timeline itself only
//  needs a daily fallback reload to keep the streak grace window and the rotating
//  prompt honest.
//

import WidgetKit
import SwiftUI

struct DreamEntry: TimelineEntry {
    let date: Date
    let snapshot: DreamSnapshot
    let prompt: String
}

struct DreamProvider: TimelineProvider {
    func placeholder(in context: Context) -> DreamEntry {
        DreamEntry(date: .now, snapshot: .sample, prompt: DreamPrompts.today())
    }

    func getSnapshot(in context: Context, completion: @escaping (DreamEntry) -> Void) {
        let snapshot = context.isPreview ? .sample : DreamSnapshot.load()
        completion(DreamEntry(date: .now, snapshot: snapshot, prompt: DreamPrompts.today()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DreamEntry>) -> Void) {
        let entry = DreamEntry(date: .now, snapshot: DreamSnapshot.load(), prompt: DreamPrompts.today())
        // Reload just after midnight so the streak's grace window and the daily
        // prompt advance even if the app isn't opened.
        let nextRefresh = Calendar.current.nextDate(
            after: .now,
            matching: DateComponents(hour: 0, minute: 1),
            matchingPolicy: .nextTime
        ) ?? .now.addingTimeInterval(60 * 60)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}
