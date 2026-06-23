//
//  QuickRecordControl.swift
//  HalfLightWidgets
//
//  A Control Center / Lock Screen control that opens HalfLight straight into a new
//  dream with dictation running — the one-tap morning capture. Backed by the same
//  QuickRecordIntent the widgets and Siri use.
//

import AppIntents
import SwiftUI
import WidgetKit

struct QuickRecordControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "LanternHours.HalfLight.QuickRecord") {
            ControlWidgetButton(action: QuickRecordIntent()) {
                Label("Record Dream", systemImage: "mic.fill")
            }
        }
        .displayName("Record a Dream")
        .description("Capture a dream the moment you wake up.")
    }
}
