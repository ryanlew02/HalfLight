//
//  QuickRecordIntent.swift
//  HalfLight
//
//  The App Intent behind the morning quick-capture. SHARED FILE — must belong to
//  both the HalfLight and HalfLightWidgets targets, since the widget/Control
//  invoke it while the app registers it as a Siri/Spotlight shortcut.
//
//  It does only one thing: foreground the app and leave a breadcrumb in the App
//  Group. The app reads that breadcrumb (QuickRecordSignal) on becoming active and
//  opens a fresh dream with dictation running.
//

import AppIntents

struct QuickRecordIntent: AppIntent {
    static var title: LocalizedStringResource = "Record a Dream"
    static var description = IntentDescription("Open HalfLight and start a new dream with voice dictation.")

    /// Bring the app to the foreground so capture can begin immediately.
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        QuickRecordSignal.request()
        return .result()
    }
}
