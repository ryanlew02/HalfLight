//
//  DreamSnapshot.swift
//  HalfLight
//
//  The render-ready slice of dreamer state shared between the app and its widget
//  extension. SHARED FILE — must belong to both the HalfLight and HalfLightWidgets
//  targets (Target Membership in the File inspector).
//
//  The app rewrites this on every change (see WidgetSnapshotWriter); the widgets
//  only ever read it. It is deliberately free of SwiftData / SwiftUI / app types
//  so the extension stays lightweight and never pulls in the Supabase stack.
//

import Foundation

/// Identifiers shared across the app group boundary.
enum SharedGroup {
    /// The App Group both targets join. Must match the `application-groups`
    /// entitlement on the app *and* the widget extension.
    static let id = "group.LanternHours.HalfLight"
}

/// A small snapshot of the journal, written by the app and read by the widgets.
struct DreamSnapshot: Codable, Equatable {
    var currentStreak: Int
    var longestStreak: Int
    var totalDreams: Int
    var lucidCount: Int
    /// Dreams recorded in the trailing 7 days.
    var weekCount: Int

    // Most recent dream — all `nil` while the journal is empty.
    var lastDreamTitle: String?
    var lastDreamMood: String?
    var lastDreamMoodSymbol: String?
    /// 0xRRGGBB tint for the last dream's mood, so the widget needn't know moods.
    var lastDreamMoodColor: UInt32?
    var lastDreamDate: Date?

    static let empty = DreamSnapshot(
        currentStreak: 0, longestStreak: 0, totalDreams: 0, lucidCount: 0, weekCount: 0,
        lastDreamTitle: nil, lastDreamMood: nil, lastDreamMoodSymbol: nil,
        lastDreamMoodColor: nil, lastDreamDate: nil
    )
}

extension DreamSnapshot {
    /// The snapshot file inside the shared App Group container.
    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedGroup.id)?
            .appendingPathComponent("dream-snapshot.json")
    }

    /// Read the latest snapshot, or `.empty` if nothing has been written yet.
    static func load() -> DreamSnapshot {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(DreamSnapshot.self, from: data)
        else { return .empty }
        return snapshot
    }

    /// Persist this snapshot atomically into the shared container.
    func save() {
        guard let url = Self.fileURL,
              let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

/// A one-shot, cross-process request to jump straight into a new dream. Set by
/// `JournalDreamIntent` (a widget or the Control, which open the entry silently)
/// or `QuickRecordIntent` (Siri, which starts dictation since the ask was spoken),
/// and consumed by the app the next time it becomes active.
enum QuickRecordSignal {
    private static let key = "pendingQuickRecordAt"
    private static let dictateKey = "pendingQuickRecordDictates"
    private static var defaults: UserDefaults? { UserDefaults(suiteName: SharedGroup.id) }

    /// Record that the dreamer asked to capture a dream from outside the app, and
    /// whether that entry point wants dictation running when it opens.
    static func request(dictating: Bool) {
        defaults?.set(Date.now.timeIntervalSince1970, forKey: key)
        defaults?.set(dictating, forKey: dictateKey)
    }

    /// Consume a pending request, returning whether it asked for dictation — or
    /// `nil` when none is pending. The freshness window guards against firing on
    /// an unrelated later launch.
    static func consume(within window: TimeInterval = 30) -> Bool? {
        guard let defaults, defaults.object(forKey: key) != nil else { return nil }
        let timestamp = defaults.double(forKey: key)
        let dictating = defaults.bool(forKey: dictateKey)
        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: dictateKey)
        guard Date.now.timeIntervalSince1970 - timestamp < window else { return nil }
        return dictating
    }
}
