import SwiftUI
import UIKit

extension View {
    func appListNavigationBar(title: String, subtitle: String) -> some View {
        navigationTitle(title)
            .navigationSubtitle(subtitle)
            .toolbarTitleDisplayMode(.large)
            .background {
                AppListNavigationBarBridge()
                    .frame(width: 0, height: 0)
            }
    }
}

/// SwiftUI owns the native titles and their scroll transition. This bridge only
/// selects leading compact titles and disables the unused additional overflow menu.
struct AppListNavigationBarBridge: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.install()
        controller.scheduleInstallation()
    }

    static func dismantleUIViewController(_ controller: Controller, coordinator: Void) {
        controller.detach()
    }

    final class Controller: UIViewController {
        private weak var installedItem: UINavigationItem?
        private var originalStyle: UINavigationItem.ItemStyle = .navigator
        private var suppressedOverflowItems: UIDeferredMenuElement?
        private var installationScheduled = false
        private var isDetached = false

        override func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = false
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            if parent != nil {
                isDetached = false
                install()
                scheduleInstallation()
            }
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            install()
            scheduleInstallation()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            install()
        }

        func install() {
            guard isDetached == false else { return }
            // Resolve this screen's ancestor, never navigationController.topViewController:
            // a covered list may still receive refresh/count updates under Reader.
            var ancestor = parent
            while let current = ancestor {
                if current.navigationController?.viewControllers.contains(where: { $0 === current }) == true {
                    install(on: current.navigationItem)
                    return
                }
                ancestor = current.parent
            }
            removeConfiguration()
        }

        private func install(on item: UINavigationItem) {
            if installedItem !== item {
                removeConfiguration()
                installedItem = item
                originalStyle = item.style
            }
            if item.style != .browser {
                item.style = .browser
            }
            // These list screens have no additional overflow commands. A non-nil
            // deferred provider creates an ellipsis even when it returns no actions.
            if let overflowItems = item.additionalOverflowItems {
                suppressedOverflowItems = overflowItems
                item.additionalOverflowItems = nil
            }
        }

        func scheduleInstallation() {
            guard installationScheduled == false, isDetached == false else { return }
            installationScheduled = true
            // SwiftUI can reconcile its toolbar after updateUIViewController.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.installationScheduled = false
                self.install()
            }
        }

        func detach() {
            isDetached = true
            removeConfiguration()
        }

        private func removeConfiguration() {
            guard let item = installedItem else { return }
            if item.style == .browser {
                item.style = originalStyle
                if item.additionalOverflowItems == nil {
                    item.additionalOverflowItems = suppressedOverflowItems
                }
            }
            installedItem = nil
            suppressedOverflowItems = nil
        }
    }
}
