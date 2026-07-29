//
//  HalfLightWidgetBundle.swift
//  HalfLightWidgets
//
//  The widget extension entry point. Registers every HalfLight widget plus the
//  journal-a-dream Control.
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
        JournalWidget()
        JournalDreamControl()
    }
}
