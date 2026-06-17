//
//  ProfileView.swift
//  HalfLight
//
//  The Profile tab: the dreamer's name, account status, and a way into
//  Settings. (Leaderboard / friends will live here later.)
//

import SwiftUI

struct ProfileView: View {
    @Environment(AuthService.self) private var auth
    @AppStorage("userName") private var userName = "Dreamer"
    @State private var showAuth = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    accountCard
                }
                .padding(20)
            }
            .background { DreamBackground() }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showAuth) {
                AuthView()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(userName)
                    .font(.dreamDisplay(28))
                Text(auth.isSignedIn ? (auth.email ?? "Signed in") : "Not signed in")
                    .font(.dreamBody(13, .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            NavigationLink {
                SettingsView()
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.title2)
                    .foregroundStyle(Color.dreamPrimary)
            }
            .accessibilityLabel("Settings")
        }
    }

    @ViewBuilder
    private var accountCard: some View {
        if auth.isSignedIn {
            HStack(spacing: DreamMetric.md) {
                Image(systemName: "checkmark.icloud.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.dreamPrimary)
                    .frame(width: 44, height: 44)
                    .background(Color.dreamPrimary.opacity(0.12), in: .circle)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Account active")
                        .font(.dreamDisplay(16, .bold))
                    Text(auth.email ?? "Your dreams are backed up")
                        .font(.dreamBody(13))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DreamMetric.lg)
            .dreamCard()
        } else {
            Button {
                showAuth = true
            } label: {
                HStack(spacing: DreamMetric.md) {
                    Image(systemName: "icloud.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.dreamPrimary)
                        .frame(width: 44, height: 44)
                        .background(Color.dreamPrimary.opacity(0.12), in: .circle)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Create an account")
                            .font(.dreamDisplay(16, .bold))
                        Text("Back up and sync your dreams")
                            .font(.dreamBody(13))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.dreamText.opacity(0.4))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DreamMetric.lg)
                .dreamCard()
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview("Light") {
    ProfileView()
        .environment(AuthService())
}

#Preview("Dark") {
    ProfileView()
        .environment(AuthService())
        .preferredColorScheme(.dark)
}
