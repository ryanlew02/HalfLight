//
//  HalfLightWidgetBundle.swift
//  HalfLightWidgets
//
//  The widget extension entry point. Registers every HalfLight widget plus the
//  quick-record Control.
//

import WidgetKit
import SwiftUI

@main
struct HalfLightWidgetBundle: WidgetBundle {
    var body: some Widget {
        StreakWidget()
        LastDreamWidget()
        StatsWidget()
        PromptWidget()
        RecordWidget()
        QuickRecordControl()
    }
}
