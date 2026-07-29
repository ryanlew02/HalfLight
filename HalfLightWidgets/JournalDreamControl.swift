//
//  JournalDreamControl.swift
//  HalfLightWidgets
//
//  A Control Center / Lock Screen control that opens HalfLight straight onto a new
//  dream entry — the one-tap morning capture, with the mic left alone so nothing
//  starts listening by itself. Backed by the same JournalDreamIntent the widgets
//  use.
//

import AppIntents
import SwiftUI
import WidgetKit

struct JournalDreamControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        // The kind is unchanged from this control's quick-record days, so controls
        // the dreamer has already placed keep working.
        StaticControlConfiguration(kind: "LanternHours.HalfLight.QuickRecord") {
            ControlWidgetButton(action: JournalDreamIntent()) {
                Label("Journal Dream", systemImage: "square.and.pencil")
            }
        }
        .displayName("Journal a Dream")
        .description("Capture a dream the moment you wake up.")
    }
}
