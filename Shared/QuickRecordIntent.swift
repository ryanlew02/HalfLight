//
//  QuickRecordIntent.swift
//  HalfLight
//
//  The App Intents behind the morning quick-capture. SHARED FILE — must belong to
//  both the HalfLight and HalfLightWidgets targets, since the widget/Control
//  invoke them while the app registers one as a Siri/Spotlight shortcut.
//
//  They do only one thing: foreground the app and leave a breadcrumb in the App
//  Group. The app reads that breadcrumb (QuickRecordSignal) on becoming active and
//  opens a fresh dream — with dictation running only when the breadcrumb asks for
//  it, which is the spoken Siri path alone.
//

import AppIntents

/// Tapping a widget or the Control: open a blank dream, keyboard and mic idle.
struct JournalDreamIntent: AppIntent {
    static var title: LocalizedStringResource = "Journal a Dream"
    static var description = IntentDescription("Open HalfLight on a new, blank dream entry.")

    /// Bring the app to the foreground so writing can begin immediately.
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        QuickRecordSignal.request(dictating: false)
        return .result()
    }
}

/// Asking Siri out loud: open a new dream with dictation already listening, since
/// the dreamer's hands are clearly not on the phone.
struct QuickRecordIntent: AppIntent {
    static var title: LocalizedStringResource = "Record a Dream"
    static var description = IntentDescription("Open HalfLight and start a new dream with voice dictation.")

    /// Bring the app to the foreground so capture can begin immediately.
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        QuickRecordSignal.request(dictating: true)
        return .result()
    }
}
