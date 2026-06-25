//
//  UsernameAvailabilityLabel.swift
//  HalfLight
//
//  Live "is this username available?" feedback, driven by
//  `AuthService.usernameStatus`. Shared by the sign-up form and the change-username
//  screen so both read identically.
//

import SwiftUI

struct UsernameAvailabilityLabel: View {
    let status: AuthService.UsernameStatus

    var body: some View {
        switch status {
        case .idle:
            EmptyView()
        case .checking:
            row(text: "Checking availability…", tint: .secondary, spinner: true)
        case .available:
            row(symbol: "checkmark.circle.fill", text: "Username is available", tint: .green)
        case .taken:
            row(symbol: "xmark.circle.fill", text: "That username is taken", tint: .red)
        case .invalid:
            row(
                symbol: "info.circle.fill",
                text: "3–20 characters: letters, numbers, or underscores.",
                tint: .secondary
            )
        }
    }

    private func row(
        symbol: String? = nil,
        text: String,
        tint: Color,
        spinner: Bool = false
    ) -> some View {
        HStack(spacing: DreamMetric.xs) {
            if spinner {
                ProgressView().controlSize(.small)
            } else if let symbol {
                Image(systemName: symbol)
            }
            Text(text)
                .font(.dreamBody(12, .medium))
        }
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
