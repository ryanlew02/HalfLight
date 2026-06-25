//
//  SwipeBackEnabler.swift
//  HalfLight
//
//  Restores the edge-swipe "back" gesture on a pushed screen whose navigation bar
//  is hidden. Hiding the bar (to draw a custom header, as the Progress screen does)
//  otherwise disables `interactivePopGestureRecognizer`; this reinstates it with the
//  same "only when there's something to pop" rule the system normally applies.
//
//  Usage: add `.enableSwipeBack()` to the pushed view.
//

import SwiftUI

#if canImport(UIKit)
import UIKit

extension View {
    func enableSwipeBack() -> some View {
        background(SwipeBackEnabler())
    }
}

private struct SwipeBackEnabler: UIViewControllerRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.backgroundColor = .clear
        controller.view.isUserInteractionEnabled = false
        context.coordinator.controller = controller
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        context.coordinator.restoreGesture()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var controller: UIViewController?

        /// Find the enclosing navigation controller and let its pop gesture fire
        /// again. Deferred to the next runloop so the controller is in the hierarchy.
        func restoreGesture() {
            DispatchQueue.main.async { [weak self] in
                guard let self, let nav = self.controller?.navigationController else { return }
                nav.interactivePopGestureRecognizer?.isEnabled = true
                nav.interactivePopGestureRecognizer?.delegate = self
            }
        }

        // Allow the swipe only when there's a screen to pop back to — matching the
        // system's default, so a swipe at the stack root does nothing.
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            (controller?.navigationController?.viewControllers.count ?? 0) > 1
        }
    }
}
#else
extension View {
    func enableSwipeBack() -> some View { self }
}
#endif
