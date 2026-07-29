//
//  BlockUser.swift
//  HalfLight
//
//  Blocking one dreamer from another — the person-to-person counterpart to a
//  moderator ban. Anyone can block anyone; it needs no moderator, and the person
//  blocked is never told.
//
//  A block is symmetric in effect: neither dreamer sees the other's dreams,
//  comments, profile or activity again, and any follow between them is dropped.
//  All of that is enforced server-side in RLS (see the user_blocks migration);
//  the app's job is to ask for confirmation, clear the local cache, and offer a
//  way back out from Settings.
//
//  The confirmation lives here rather than in each screen because the feed, the
//  comments sheet and public profiles all offer the same action.
//

import SwiftUI

extension View {
    /// Attach the "Block @handle?" confirmation. Setting `handle` to a @handle
    /// presents it; `perform` runs only if the dreamer confirms.
    func blockConfirmation(
        handle: Binding<String?>,
        perform: @escaping (String) async -> Void
    ) -> some View {
        modifier(BlockConfirmation(handle: handle, perform: perform))
    }
}

private struct BlockConfirmation: ViewModifier {
    @Binding var handle: String?
    let perform: (String) async -> Void

    /// Shown after a block lands, so the dreamer knows it took effect — the feed
    /// just quietly loses their dreams otherwise.
    @State private var confirmedHandle: String?

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                blockTitle,
                isPresented: Binding(
                    get: { handle != nil },
                    set: { if !$0 { handle = nil } }
                ),
                titleVisibility: .visible,
                presenting: handle
            ) { target in
                Button("Block", role: .destructive) {
                    SoundManager.shared.play(.tap)
                    Task {
                        await perform(target)
                        confirmedHandle = target
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("You won't see their dreams or comments, and they won't see yours. They aren't told about this, and you can undo it in Settings.")
            }
            .alert(
                "Blocked",
                isPresented: Binding(
                    get: { confirmedHandle != nil },
                    set: { if !$0 { confirmedHandle = nil } }
                ),
                presenting: confirmedHandle
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { target in
                Text("You won't see @\(target) around HalfLight anymore. Unblock them any time from Settings › Account › Blocked Accounts.")
            }
    }

    // Phrased in full rather than as "Block @handle?" so it doesn't collide with
    // the context-menu label ("Block @handle"): near-identical keys generate the
    // same Swift symbol and fail the string-catalog build.
    private var blockTitle: String {
        guard let handle else { return String(localized: "Block this dreamer?") }
        return String(localized: "Are you sure you want to block @\(handle)?")
    }
}
