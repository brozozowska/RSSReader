import SwiftUI
import UIKit

/// Keeps the native interactive transition available while the list's search UI is active.
struct ArticleSearchBackNavigationBridge: UIViewControllerRepresentable {
    let isEnabled: Bool
    let backGestureBegan: @MainActor () -> Void

    func makeUIViewController(context: Context) -> BridgeController {
        BridgeController()
    }

    func updateUIViewController(_ controller: BridgeController, context: Context) {
        controller.isEnabled = isEnabled
        controller.backGestureBegan = backGestureBegan
        controller.installIfNeeded()
    }

    static func dismantleUIViewController(_ controller: BridgeController, coordinator: Void) {
        controller.detach()
    }

    final class BridgeController: UIViewController {
        var isEnabled = false
        var backGestureBegan: (@MainActor () -> Void)?
        private var proxy: ArticleSearchBackGestureDelegate?
        private weak var installedGesture: UIGestureRecognizer?

        override func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = false
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            installIfNeeded()
        }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            detach()
        }

        func installIfNeeded() {
            guard isEnabled,
                  let navigationController,
                  let gesture = navigationController.interactivePopGestureRecognizer else {
                detach()
                return
            }
            // SwiftUI can refresh its gesture delegate when navigation/search chrome changes.
            if installedGesture === gesture, gesture.delegate === proxy { return }
            detach()
            let proxy = ArticleSearchBackGestureDelegate(
                navigationController: navigationController,
                originalDelegate: gesture.delegate,
                ownsTopController: { [weak self] topController in
                    var controller: UIViewController? = self
                    while let current = controller {
                        if current === topController { return true }
                        controller = current.parent
                    }
                    return false
                }
            )
            self.proxy = proxy
            installedGesture = gesture
            gesture.delegate = proxy
            gesture.addTarget(self, action: #selector(handleBackGesture(_:)))
        }

        func detach() {
            guard let gesture = installedGesture else { return }
            gesture.removeTarget(self, action: #selector(handleBackGesture(_:)))
            if gesture.delegate === proxy {
                gesture.delegate = proxy?.originalDelegate
            }
            installedGesture = nil
            proxy = nil
        }

        @objc private func handleBackGesture(_ gesture: UIGestureRecognizer) {
            if gesture.state == .began {
                backGestureBegan?()
            }
        }
    }
}

@MainActor
final class ArticleSearchBackGestureDelegate: NSObject, UIGestureRecognizerDelegate {
    weak var originalDelegate: (any UIGestureRecognizerDelegate)?
    private weak var navigationController: UINavigationController?
    private let ownsTopController: (UIViewController) -> Bool

    init(
        navigationController: UINavigationController,
        originalDelegate: (any UIGestureRecognizerDelegate)?,
        ownsTopController: @escaping (UIViewController) -> Bool
    ) {
        self.navigationController = navigationController
        self.originalDelegate = originalDelegate
        self.ownsTopController = ownsTopController
    }

    private var allowsActiveSearchBack: Bool {
        guard let navigationController,
              navigationController.viewControllers.count > 1,
              navigationController.transitionCoordinator == nil,
              let topController = navigationController.topViewController,
              ownsTopController(topController),
              let searchController = topController.navigationItem.searchController,
              searchController.isActive,
              topController.presentedViewController == nil
                || topController.presentedViewController === searchController,
              navigationController.presentedViewController == nil
                || navigationController.presentedViewController === searchController else {
            return false
        }
        return true
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard allowsActiveSearchBack else {
            return originalDelegate?.gestureRecognizerShouldBegin?(gestureRecognizer) ?? false
        }
        if let pan = gestureRecognizer as? UIPanGestureRecognizer,
           let view = gestureRecognizer.view {
            let velocity = pan.velocity(in: view)
            let direction: CGFloat = view.effectiveUserInterfaceLayoutDirection == .rightToLeft ? -1 : 1
            guard velocity.x * direction > abs(velocity.y) else { return false }
        }
        // Only lift the search veto for this list. UIKit owns the interactive pop.
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if touch.type == .direct, allowsActiveSearchBack { return true }
        return originalDelegate?.gestureRecognizer?(gestureRecognizer, shouldReceive: touch) ?? true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive press: UIPress) -> Bool {
        originalDelegate?.gestureRecognizer?(gestureRecognizer, shouldReceive: press) ?? true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive event: UIEvent) -> Bool {
        originalDelegate?.gestureRecognizer?(gestureRecognizer, shouldReceive: event) ?? true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        originalDelegate?.gestureRecognizer?(
            gestureRecognizer, shouldRecognizeSimultaneouslyWith: otherGestureRecognizer
        ) ?? false
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        originalDelegate?.gestureRecognizer?(
            gestureRecognizer, shouldRequireFailureOf: otherGestureRecognizer
        ) ?? false
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        originalDelegate?.gestureRecognizer?(
            gestureRecognizer, shouldBeRequiredToFailBy: otherGestureRecognizer
        ) ?? false
    }
}
