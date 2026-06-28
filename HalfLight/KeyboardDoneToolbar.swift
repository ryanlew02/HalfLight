//
//  KeyboardDoneToolbar.swift
//  HalfLight
//
//  Two ways to dismiss the keyboard, used app-wide:
//
//  1. A "Done" button above the keyboard (`KeyboardDoneButton` / the
//     `.keyboardDoneToolbar()` modifier). For screens that already have a
//     `.toolbar { … }`, add `KeyboardDoneButton()` *inside* that block — SwiftUI
//     does not reliably merge two separate `.toolbar` modifiers, so a standalone
//     `.keyboardDoneToolbar()` next to an existing toolbar can silently not show.
//     Screens with no other toolbar can use the `.keyboardDoneToolbar()` modifier.
//
//  2. Tap anywhere outside a field to dismiss (`.dismissKeyboardOnTapOutside()`).
//     Installed once at the app root; a window-level tap recognizer that ignores
//     touches on text inputs (so switching fields still works) and passes touches
//     through to everything else.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// The "Done" item for the keyboard accessory bar. Drop into any `.toolbar { }`.
struct KeyboardDoneButton: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done") { dismissKeyboard() }
                .fontWeight(.semibold)
                .foregroundStyle(Color.dreamPrimary)
        }
    }
}

extension View {
    /// Adds a single "Done" button above the keyboard. Use only on screens that
    /// have no other `.toolbar`; otherwise add `KeyboardDoneButton()` inside the
    /// existing toolbar instead.
    func keyboardDoneToolbar() -> some View {
        toolbar { KeyboardDoneButton() }
    }

    /// Dismiss the keyboard when the dreamer taps anywhere that isn't a text
    /// field. Attach once near the app root — it installs a recognizer on the
    /// window, so it covers every screen and presented sheet.
    func dismissKeyboardOnTapOutside() -> some View {
        #if canImport(UIKit)
        background(KeyboardDismissInstaller().frame(width: 0, height: 0))
        #else
        self
        #endif
    }
}

/// Resign the current first responder, dismissing the keyboard from anywhere.
@MainActor
func dismissKeyboard() {
    #if canImport(UIKit)
    UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
    )
    #endif
}

#if canImport(UIKit)
/// Installs a tap recognizer on the host window that dismisses the keyboard on a
/// tap outside any text input. Rendered as a zero-size, non-interactive backer.
private struct KeyboardDismissInstaller: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        DispatchQueue.main.async { context.coordinator.install(on: view.window) }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // The window may not be set on the first layout pass; retry until it is.
        if context.coordinator.gesture == nil {
            DispatchQueue.main.async { context.coordinator.install(on: uiView.window) }
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var gesture: UITapGestureRecognizer?

        func install(on window: UIWindow?) {
            guard let window, gesture == nil else { return }
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            // Don't swallow the touch — buttons, lists and scrolling keep working.
            tap.cancelsTouchesInView = false
            tap.delegate = self
            window.addGestureRecognizer(tap)
            gesture = tap
        }

        @objc private func handleTap() { dismissKeyboard() }

        // Ignore taps that land inside a text field / editor, so tapping straight
        // from one field to another moves focus instead of dismissing first.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            var view = touch.view
            while let current = view {
                if current is UIControl || current is UITextView { return false }
                view = current.superview
            }
            return true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { true }
    }
}
#endif
