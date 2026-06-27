//
//  ReportReason.swift
//  HalfLight
//
//  The reasons a dreamer can pick when reporting a feed post or a comment. The
//  raw value is what gets stored in the `feed_reports.reason` column; the label
//  is what's shown in the report menu.
//

import Foundation

enum ReportReason: String, CaseIterable, Identifiable, Sendable {
    case spam
    case harassment
    case inappropriate
    case other

    var id: String { rawValue }

    /// The menu label shown to the reporter.
    var label: String {
        switch self {
        case .spam:          return "Spam or scam"
        case .harassment:    return "Harassment or hate"
        case .inappropriate: return "Inappropriate content"
        case .other:         return "It is something else"
        }
    }
}
