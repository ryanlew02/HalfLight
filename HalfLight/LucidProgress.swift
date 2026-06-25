//
//  LucidProgress.swift
//  HalfLight
//
//  Tracks which lucid lessons the dreamer has completed and derives each lesson's
//  unlock status (completed / current / locked) across the whole curriculum, so
//  the path unlocks one lesson at a time. Keeps `lucidSectionsCompleted` — the
//  count the XP economy and achievements read — in step with completed lessons.
//

import Foundation

enum LucidLessonStatus {
    case completed
    case current
    case locked
}

enum LucidProgress {
    private static let completedKey = "lucidCompletedLessons"
    /// The count other systems already read for XP and achievements.
    private static let countKey = "lucidSectionsCompleted"

    static func completedIDs() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: completedKey) ?? [])
    }

    static func isCompleted(_ id: String) -> Bool {
        completedIDs().contains(id)
    }

    /// The first not-yet-completed lesson in path order — the single "current"
    /// node. `nil` once every lesson is done.
    static func currentLessonID() -> String? {
        LucidCurriculum.allLessons.first { !isCompleted($0.id) }?.id
    }

    static func status(for id: String) -> LucidLessonStatus {
        if isCompleted(id) { return .completed }
        if id == currentLessonID() { return .current }
        return .locked
    }

    /// Mark a lesson complete and sync the lucid lesson count used elsewhere.
    /// Returns `true` only when this was a brand-new completion (i.e. XP was
    /// actually earned), so the caller can celebrate it; re-finishing an
    /// already-completed lesson returns `false`.
    @discardableResult
    static func complete(_ id: String) -> Bool {
        var ids = completedIDs()
        guard ids.insert(id).inserted else { return false }
        write(ids)
        return true
    }

    /// Overwrite local progress with exactly `ids` (used when pulling the
    /// account's progress down on sign-in / launch).
    static func replaceAll(_ ids: some Sequence<String>) {
        write(Set(ids))
    }

    /// Wipe local progress back to zero (used on sign-out — the account keeps it).
    static func clear() {
        UserDefaults.standard.removeObject(forKey: completedKey)
        UserDefaults.standard.removeObject(forKey: countKey)
    }

    /// Persist a set of completed lesson IDs and the derived count together, so
    /// the two keys never drift apart.
    private static func write(_ ids: Set<String>) {
        UserDefaults.standard.set(Array(ids), forKey: completedKey)
        UserDefaults.standard.set(ids.count, forKey: countKey)
    }
}
