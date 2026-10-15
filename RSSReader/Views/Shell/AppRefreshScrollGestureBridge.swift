import SwiftUI
import UIKit

/// Release/cancellation comes from the existing scroll view's pan recognizer.
/// It does not replace a delegate, add a competing gesture, or change insets.
struct AppRefreshScrollGestureBridge: UIViewControllerRepresentable {
    var isEnabled = true
    let isRefreshing: Bool
    let pullProgressChanged: @MainActor (Double) -> Void
    let releaseAction: @MainActor () -> Void

    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.isEnabled = isEnabled && isRefreshing == false
        controller.pullProgressChanged = pullProgressChanged
        controller.releaseAction = releaseAction
        controller.install()
    }

    static func dismantleUIViewController(_ controller: Controller, coordinator: Void) {
        controller.detach()
    }

    final class Controller: UIViewController {
        var isEnabled = true {
            didSet {
                if isEnabled == false { interaction.cancel() }
            }
        }
        var pullProgressChanged: (@MainActor (Double) -> Void)?
        var releaseAction: (@MainActor () -> Void)?
        private weak var scrollView: UIScrollView?
        private var interaction = AppRefreshPullGestureState()

        override func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = false
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            install()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            install()
        }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            detach()
        }

        func install() {
            guard viewIfLoaded?.window != nil else { return }
            var ancestor = parent
            while let current = ancestor {
                if current.navigationController?.viewControllers.contains(where: { $0 === current }) == true {
                    let candidate = current.contentScrollView(for: .top)
                        ?? Self.findListScrollView(in: current.view)
                    attach(to: candidate)
                    return
                }
                ancestor = current.parent
            }
            attach(to: nil)
        }

        private static func findListScrollView(in view: UIView) -> UIScrollView? {
            // Stop at a list's scroll view; never inspect its cells or nested content.
            if let list = view as? UICollectionView { return list }
            if let list = view as? UITableView { return list }
            for child in view.subviews {
                if let list = findListScrollView(in: child) { return list }
            }
            return nil
        }

        func attach(to newScrollView: UIScrollView?) {
            guard scrollView !== newScrollView else { return }
            detach()
            scrollView = newScrollView
            newScrollView?.panGestureRecognizer.addTarget(self, action: #selector(panChanged(_:)))
        }

        func detach() {
            scrollView?.panGestureRecognizer.removeTarget(self, action: #selector(panChanged(_:)))
            scrollView = nil
            if interaction.cancel() {
                pullProgressChanged?(0)
            }
        }

        @objc private func panChanged(_ pan: UIPanGestureRecognizer) {
            guard let scrollView else { return }
            let event: AppRefreshPullGestureState.Event
            switch pan.state {
            case .began: event = .began
            case .changed: event = .changed
            case .ended: event = .ended
            case .cancelled, .failed: event = .cancelled
            default: return
            }
            let result = interaction.handle(
                event,
                contentOffsetY: scrollView.contentOffset.y,
                contentInsetTop: scrollView.adjustedContentInset.top,
                isEnabled: isEnabled
            )
            pullProgressChanged?(result.progress)
            if result.shouldRefresh {
                releaseAction?()
            }
        }
    }
}

struct AppRefreshPullGestureState {
    enum Event {
        case began
        case changed
        case ended
        case cancelled
    }

    struct Result {
        let progress: Double
        let shouldRefresh: Bool
    }

    static let pullThreshold: CGFloat = 72
    private var isTracking = false

    @discardableResult
    mutating func cancel() -> Bool {
        let wasTracking = isTracking
        isTracking = false
        return wasTracking
    }

    mutating func handle(
        _ event: Event,
        contentOffsetY: CGFloat,
        contentInsetTop: CGFloat,
        isEnabled: Bool
    ) -> Result {
        guard isEnabled else {
            cancel()
            return Result(progress: 0, shouldRefresh: false)
        }
        switch event {
        case .began:
            isTracking = true
        case .cancelled:
            cancel()
            return Result(progress: 0, shouldRefresh: false)
        case .changed, .ended:
            guard isTracking else { return Result(progress: 0, shouldRefresh: false) }
        }

        let overscroll = -(contentOffsetY + contentInsetTop)
        let progress = overscroll.isFinite ? min(max(Double(overscroll / Self.pullThreshold), 0), 1) : 0
        if event == .ended {
            cancel()
            return Result(progress: progress == 1 ? 1 : 0, shouldRefresh: progress == 1)
        }
        return Result(progress: progress, shouldRefresh: false)
    }
}
