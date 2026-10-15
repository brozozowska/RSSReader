import SwiftUI
import UIKit

extension View {
    func appListNavigationBar(
        title: String,
        subtitle: String,
        refreshState: AppRefreshIndicatorState
    ) -> some View {
        navigationTitle(title)
            .navigationSubtitle(subtitle)
            .toolbarTitleDisplayMode(.large)
            .background {
                AppListNavigationBarBridge(refreshState: refreshState)
                    .frame(width: 0, height: 0)
            }
    }
}

/// SwiftUI owns the native titles and their scroll transition. The bridge owns
/// a stable center item for refresh, leading compact titles and overflow suppression.
struct AppListNavigationBarBridge: UIViewControllerRepresentable {
    let refreshState: AppRefreshIndicatorState

    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.updateRefreshState(refreshState)
        controller.install()
        controller.scheduleInstallation()
    }

    static func dismantleUIViewController(_ controller: Controller, coordinator: Void) {
        controller.detach()
    }

    /// A native trailing item reserves the space from the bar center to existing
    /// trailing controls. The ring sits at its semantic leading edge; all sizing
    /// uses public view coordinates, without reaching into UIKit's title views.
    final class RefreshHostingView: UIView {
        let content: UIView
        private var reservedWidth: CGFloat = 32
        private lazy var widthConstraint = widthAnchor.constraint(equalToConstant: 32)

        init(content: UIView) {
            self.content = content
            super.init(frame: CGRect(x: 0, y: 0, width: 32, height: 32))
            backgroundColor = .clear
            content.backgroundColor = .clear
            addSubview(content)
            NSLayoutConstraint.activate([
                widthConstraint,
                heightAnchor.constraint(equalToConstant: 32)
            ])
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override var intrinsicContentSize: CGSize { CGSize(width: reservedWidth, height: 32) }

        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool { false }

        override func layoutSubviews() {
            super.layoutSubviews()
            updatePlacement()
            let centerX = containingBar.map { convert(CGPoint(x: $0.bounds.midX, y: 0), from: $0).x }
                ?? bounds.midX
            content.frame = CGRect(x: centerX - 16, y: 0, width: 32, height: 32)
        }

        private var containingBar: UINavigationBar? {
            var ancestor = superview
            while let current = ancestor, current is UINavigationBar == false {
                ancestor = current.superview
            }
            return ancestor as? UINavigationBar
        }

        func updatePlacement() {
            guard let bar = containingBar, bar.bounds.width > 0 else { return }
            let frameInBar = convert(bounds, to: bar)
            // UIKit's button wrappers may force LTR internally. Read the bar's
            // semantic direction rather than inheriting that implementation detail.
            let isRightToLeft = bar.effectiveUserInterfaceLayoutDirection == .rightToLeft
            let width = max(32, isRightToLeft
                ? bar.bounds.midX - frameInBar.minX + 16
                : frameInBar.maxX - bar.bounds.midX + 16)
            guard abs(width - reservedWidth) > 0.5 else { return }
            reservedWidth = width
            widthConstraint.constant = width
            invalidateIntrinsicContentSize()
            setNeedsLayout()
            bar.setNeedsLayout()
        }
    }

    final class Controller: UIViewController {
        private weak var installedItem: UINavigationItem?
        private var originalStyle: UINavigationItem.ItemStyle = .navigator
        private var suppressedOverflowItems: UIDeferredMenuElement?
        private var wrappedTrailingItems: (group: UIBarButtonItemGroup, items: [UIBarButtonItem])?
        private var installationScheduled = false
        private var isDetached = false
        private var refreshState: AppRefreshIndicatorState = .idle
        private lazy var refreshContentView = refreshConfiguration.makeContentView()
        private lazy var refreshHostingView = RefreshHostingView(content: refreshContentView)
        private lazy var refreshItem: UIBarButtonItem = {
            let item = UIBarButtonItem(customView: refreshHostingView)
            item.hidesSharedBackground = true
            return item
        }()
        private lazy var refreshGroup: UIBarButtonItemGroup = {
            // On the current SDK, iPhone moves centerItemGroups into overflow
            // even in browser style, including items with ordinary SF Symbols.
            // A trailing custom view reserves room up to the bar's center, so
            // UIKit also truncates native leading titles before the indicator.
            let group = UIBarButtonItemGroup.fixedGroup(items: [refreshItem])
            group.alwaysAvailable = false
            group.isHidden = !refreshState.isVisible
            return group
        }()

        private var refreshConfiguration: UIHostingConfiguration<some View, EmptyView> {
            UIHostingConfiguration {
                AppRefreshIndicator(state: refreshState, size: 24, lineWidth: 2.5)
                    .frame(width: 32, height: 32)
                    .allowsHitTesting(false)
            }
            .margins(.all, 0)
        }

        func updateRefreshState(_ state: AppRefreshIndicatorState) {
            guard isDetached == false, refreshState != state else { return }
            refreshState = state
            // UIHostingConfiguration participates in the bar's traits and owns
            // its SwiftUI hosting. It is not a zero-sized child of this bridge.
            refreshContentView.configuration = refreshConfiguration
            refreshGroup.isHidden = !state.isVisible
        }

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
            // Retain hosting identity, but hide the whole group when idle so
            // native compact titles can use the full available bar width.
            if item.trailingItemGroups.contains(where: { $0 === refreshGroup }) == false {
                var groups = item.trailingItemGroups
                // UIKit keeps the legacy arrays and the group APIs separately;
                // setting groups would otherwise discard existing raw buttons.
                if groups.isEmpty, let items = item.rightBarButtonItems, items.isEmpty == false {
                    let group = UIBarButtonItemGroup.fixedGroup(items: items)
                    wrappedTrailingItems = (group, items)
                    groups = [group]
                }
                item.trailingItemGroups = [refreshGroup] + groups
            }
            refreshHostingView.updatePlacement()
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
            updateRefreshState(.idle)
            isDetached = true
            removeConfiguration()
        }

        private func removeConfiguration() {
            guard let item = installedItem else { return }
            let groups = item.trailingItemGroups.filter { $0 !== refreshGroup }
            if let wrapped = wrappedTrailingItems,
               groups.count == 1, groups.first === wrapped.group,
               wrapped.group.barButtonItems.elementsEqual(wrapped.items, by: { $0 === $1 }) {
                item.rightBarButtonItems = wrapped.items
            } else if groups.count != item.trailingItemGroups.count {
                item.trailingItemGroups = groups
            }
            wrappedTrailingItems = nil
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
