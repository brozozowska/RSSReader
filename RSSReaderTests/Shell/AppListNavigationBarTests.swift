import SwiftUI
import Testing
import UIKit
@testable import RSSReader

@Suite("Shell / List Navigation Bar")
@MainActor
struct AppListNavigationBarTests {
    @Test
    func configuresOwnNavigationItemWhileReaderIsOnTop() throws {
        let list = UIViewController()
        let reader = UIViewController()
        let navigation = UINavigationController(rootViewController: list)
        navigation.setViewControllers([list, reader], animated: false)
        list.navigationItem.title = "Feed"
        list.navigationItem.subtitle = "17 unread"
        list.navigationItem.largeTitleDisplayMode = .always
        let search = UISearchController()
        list.navigationItem.searchController = search
        let settings = UIBarButtonItem(title: "Settings", primaryAction: nil)
        let filter = UIBarButtonItem(title: "Filter", primaryAction: nil)
        list.navigationItem.leftBarButtonItem = settings
        list.navigationItem.rightBarButtonItem = filter
        let bridge = attachBridge(to: list)
        defer { bridge.detach() }

        bridge.updateRefreshState(.refreshing)
        bridge.install()
        #expect(list.navigationItem.style == .browser)
        #expect(list.navigationItem.title == "Feed")
        #expect(list.navigationItem.subtitle == "17 unread")
        #expect(list.navigationItem.largeTitleDisplayMode == .always)
        #expect(list.navigationItem.searchController === search)
        #expect(list.navigationItem.leftBarButtonItem === settings)
        #expect(list.navigationItem.trailingItemGroups.flatMap(\.barButtonItems).contains { $0 === filter })
        let group = try #require(list.navigationItem.trailingItemGroups.first)
        #expect(group.barButtonItems.count == 1)
        #expect(group.representativeItem == nil)
        #expect(group.alwaysAvailable == false)
        #expect(reader.navigationItem.style == .navigator)
        #expect(reader.navigationItem.trailingItemGroups.isEmpty)
        #expect(navigation.topViewController === reader)
    }

    @Test
    func suppressesUnusedOverflowProviderAndReconcilesToolbarUpdates() async throws {
        let screen = UIViewController()
        let navigation = UINavigationController(rootViewController: screen)
        let emptyMenu = UIDeferredMenuElement { completion in completion([]) }
        screen.navigationItem.additionalOverflowItems = emptyMenu
        let bridge = attachBridge(to: screen)
        let group = try #require(screen.navigationItem.trailingItemGroups.first)
        #expect(screen.navigationItem.additionalOverflowItems == nil)

        // Model SwiftUI replacing the native toolbar after representable update.
        let rebuiltMenu = UIDeferredMenuElement { completion in completion([]) }
        screen.navigationItem.additionalOverflowItems = rebuiltMenu
        screen.navigationItem.trailingItemGroups = []
        screen.navigationItem.style = .navigator
        bridge.scheduleInstallation()
        await nextMainQueueTurn()
        bridge.install()
        #expect(screen.navigationItem.style == .browser)
        #expect(screen.navigationItem.additionalOverflowItems == nil)
        #expect(screen.navigationItem.trailingItemGroups.count == 1)
        #expect(screen.navigationItem.trailingItemGroups.first === group)
        bridge.detach()
        #expect(screen.navigationItem.style == .navigator)
        #expect(screen.navigationItem.additionalOverflowItems === rebuiltMenu)
        #expect(screen.navigationItem.trailingItemGroups.isEmpty)
        bridge.install()
        #expect(screen.navigationItem.style == .navigator)
        #expect(navigation.topViewController === screen)
    }

    @Test
    func reparentingMovesOnlyOwnCenterItemAndRestoresOldItem() throws {
        let first = UIViewController()
        let second = UIViewController()
        let navigation = UINavigationController(rootViewController: first)
        navigation.setViewControllers([first, second], animated: false)
        let originalMenu = UIDeferredMenuElement { completion in completion([]) }
        first.navigationItem.additionalOverflowItems = originalMenu
        let bridge = attachBridge(to: first)
        let group = try #require(first.navigationItem.trailingItemGroups.first)

        bridge.willMove(toParent: nil)
        bridge.removeFromParent()
        second.addChild(bridge)
        bridge.didMove(toParent: second)
        bridge.install()
        #expect(first.navigationItem.style == .navigator)
        #expect(first.navigationItem.additionalOverflowItems === originalMenu)
        #expect(first.navigationItem.trailingItemGroups.isEmpty)
        #expect(second.navigationItem.style == .browser)
        #expect(second.navigationItem.trailingItemGroups.first === group)
        bridge.detach()
        #expect(second.navigationItem.style == .navigator)
        #expect(second.navigationItem.trailingItemGroups.isEmpty)
    }

    @Test
    func teardownPreservesConfigurationAndItemsFromAnotherOwner() {
        let screen = UIViewController()
        let navigation = UINavigationController(rootViewController: screen)
        let bridge = attachBridge(to: screen)
        let foreignMenu = UIDeferredMenuElement { completion in completion([]) }
        let foreignGroup = UIBarButtonItemGroup(
            barButtonItems: [UIBarButtonItem(title: "Other", primaryAction: nil)],
            representativeItem: nil
        )
        screen.navigationItem.style = .editor
        screen.navigationItem.additionalOverflowItems = foreignMenu
        screen.navigationItem.trailingItemGroups.append(foreignGroup)
        bridge.detach()
        #expect(screen.navigationItem.style == .editor)
        #expect(screen.navigationItem.additionalOverflowItems === foreignMenu)
        #expect(screen.navigationItem.trailingItemGroups.count == 1)
        #expect(screen.navigationItem.trailingItemGroups.first === foreignGroup)
        #expect(navigation.topViewController === screen)
    }

    @Test
    func centerItemKeepsHostingAndSizeAcrossEntireRefreshLifecycle() throws {
        let screen = UIViewController()
        let navigation = UINavigationController(rootViewController: screen)
        let bridge = attachBridge(to: screen)
        defer { bridge.detach() }
        let group = try #require(screen.navigationItem.trailingItemGroups.first)
        let item = try #require(group.barButtonItems.first)
        let content = try #require(item.customView)
        #expect(item.hidesSharedBackground)
        let hosting = try #require(content as? AppListNavigationBarBridge.RefreshHostingView)
        #expect(hosting.content is any UIContentView)
        #expect(hosting.point(inside: CGPoint(x: 16, y: 16), with: nil) == false)

        for state: AppRefreshIndicatorState in [
            .pulling(progress: 0.5), .ready, .pulling(progress: 0.3),
            .idle, .refreshing, .idle, .pulling(progress: 0.8), .ready, .refreshing, .idle
        ] {
            bridge.updateRefreshState(state)
            bridge.install()
            #expect(screen.navigationItem.trailingItemGroups.count == 1)
            #expect(screen.navigationItem.trailingItemGroups.first === group)
            #expect(group.barButtonItems.first === item)
            #expect(group.isHidden == !state.isVisible)
            #expect(item.customView === content)
            #expect(content.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize) == CGSize(width: 32, height: 32))
            #expect(screen.navigationItem.additionalOverflowItems == nil)
        }
        #expect(navigation.topViewController === screen)
    }

    @Test
    func separateColumnsDoNotShareHostingOrCleanUpEachOther() throws {
        let sidebar = UIViewController()
        let articles = UIViewController()
        let sidebarNavigation = UINavigationController(rootViewController: sidebar)
        let articleNavigation = UINavigationController(rootViewController: articles)
        let sidebarBridge = attachBridge(to: sidebar)
        let articleBridge = attachBridge(to: articles)
        defer { articleBridge.detach() }
        let sidebarGroup = try #require(sidebar.navigationItem.trailingItemGroups.first)
        let articleGroup = try #require(articles.navigationItem.trailingItemGroups.first)
        #expect(sidebarGroup !== articleGroup)
        #expect(sidebarGroup.barButtonItems.first?.customView !== articleGroup.barButtonItems.first?.customView)
        sidebarBridge.updateRefreshState(.refreshing)
        articleBridge.updateRefreshState(.pulling(progress: 0.7))
        sidebarBridge.detach()
        #expect(sidebar.navigationItem.trailingItemGroups.isEmpty)
        #expect(articles.navigationItem.trailingItemGroups.first === articleGroup)
        #expect(sidebarNavigation.topViewController === sidebar)
        #expect(articleNavigation.topViewController === articles)
    }

    @Test
    func pendingInstallationCannotReinstallAfterTeardown() async {
        let screen = UIViewController()
        let navigation = UINavigationController(rootViewController: screen)
        let bridge = attachBridge(to: screen)
        bridge.scheduleInstallation()
        bridge.detach()
        await nextMainQueueTurn()
        bridge.updateRefreshState(.refreshing)
        #expect(screen.navigationItem.style == .navigator)
        #expect(screen.navigationItem.trailingItemGroups.isEmpty)
        #expect(navigation.topViewController === screen)
    }

    @Test(arguments: [375.0, 402.0, 768.0], [false, true])
    func customHostingIsAttachedToNativeBar(width: Double, isRTL: Bool) async throws {
        for largeTitle in [false, true] {
            for category in [UIContentSizeCategory.large, .accessibilityExtraExtraExtraLarge] {
                for isSidebar in [false, true] {
                    try await verifyNativeLayout(width: width, isRTL: isRTL, largeTitle: largeTitle, category: category, isSidebar: isSidebar)
                }
            }
        }
    }

    private func verifyNativeLayout(
        width: Double, isRTL: Bool, largeTitle: Bool, category: UIContentSizeCategory, isSidebar: Bool
    ) async throws {
        let screen = UIViewController()
        let title = isSidebar ? "Feeds" : String(repeating: "Long feed title ", count: 4)
        screen.navigationItem.title = title
        screen.navigationItem.subtitle = "17 unread"
        screen.navigationItem.largeTitleDisplayMode = largeTitle ? .always : .never
        screen.navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "gearshape"), primaryAction: nil
        )
        let controls = [
            UIBarButtonItem(image: UIImage(systemName: "plus"), primaryAction: nil),
            UIBarButtonItem(image: UIImage(systemName: "line.3.horizontal.decrease"), primaryAction: nil)
        ]
        screen.navigationItem.rightBarButtonItems = isSidebar ? controls : []
        let navigation = UINavigationController(rootViewController: screen)
        navigation.traitOverrides.preferredContentSizeCategory = category
        if width == 768 {
            navigation.traitOverrides.userInterfaceIdiom = .pad
            navigation.traitOverrides.horizontalSizeClass = .regular
        }
        navigation.view.semanticContentAttribute = isRTL ? .forceRightToLeft : .forceLeftToRight
        navigation.navigationBar.semanticContentAttribute = isRTL ? .forceRightToLeft : .forceLeftToRight
        navigation.navigationBar.prefersLargeTitles = true
        screen.navigationItem.style = .browser
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 874))
        window.rootViewController = navigation
        window.isHidden = false
        navigation.view.layoutIfNeeded()
        let bridge = attachBridge(to: screen)
        bridge.updateRefreshState(.ready)
        defer {
            bridge.detach()
            window.isHidden = true
        }
        navigation.view.frame = window.bounds
        navigation.view.layoutIfNeeded()
        await nextMainQueueTurn()
        navigation.view.layoutIfNeeded()

        let group = try #require(screen.navigationItem.trailingItemGroups.first)
        let hosting = try #require(group.barButtonItems.first?.customView as? AppListNavigationBarBridge.RefreshHostingView)
        #expect(screen.navigationItem.style == .browser)
        #expect(screen.navigationItem.titleView == nil)
        #expect(hosting.isDescendant(of: navigation.navigationBar))
        #expect(hosting.content.bounds.size == CGSize(width: 32, height: 32))
        #expect(hosting.bounds.insetBy(dx: -0.5, dy: -0.5).contains(hosting.content.frame))
        let indicatorFrame = hosting.content.convert(hosting.content.bounds, to: navigation.navigationBar)
        #expect(abs(indicatorFrame.midX - navigation.navigationBar.bounds.midX) < 1)
        #expect(hosting.isHidden == false)
        #expect(group.isDisplayingRepresentativeItem == false)
        #expect(screen.navigationItem.centerItemGroups.isEmpty)
        #expect(screen.navigationItem.overflowPresentationSource == nil)
        let retainedControls = screen.navigationItem.trailingItemGroups.flatMap(\.barButtonItems)
        for control in isSidebar ? controls : [] { #expect(retainedControls.contains { $0 === control }) }
        let labels = visibleSubviews(in: navigation.navigationBar).compactMap { $0 as? UILabel }
            .filter { $0.text == title || $0.text == "17 unread" }
        #expect(labels.isEmpty == false)
        for label in labels {
            #expect(label.convert(label.bounds, to: navigation.navigationBar).intersects(indicatorFrame) == false)
        }
        let buttons = visibleSubviews(in: navigation.navigationBar).compactMap { $0 as? UIControl }
        for button in buttons where hosting.isDescendant(of: button) == false
            && button.isDescendant(of: hosting) == false {
            #expect(button.convert(button.bounds, to: navigation.navigationBar).intersects(indicatorFrame) == false)
        }
        bridge.detach()
        if isSidebar {
            #expect(screen.navigationItem.rightBarButtonItems?.elementsEqual(controls, by: { $0 === $1 }) == true)
        }
    }

    @Test
    func swiftUIToolbarReconciliationKeepsNativeCenterHosting() async throws {
        let host = UIHostingController(rootView: navigationFixture(state: .ready, title: "Feed"))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()
        await nextMainQueueTurn()
        host.view.layoutIfNeeded()

        let navigation = try #require(navigationController(in: host))
        let item = try #require(navigation.topViewController?.navigationItem)
        let scrollView = try #require(visibleSubviews(in: navigation.view).compactMap { $0 as? UIScrollView }.first)
        let initialInsets = scrollView.adjustedContentInset
        let initialOffset = scrollView.contentOffset
        let search = try #require(item.searchController)
        let originalControls = item.trailingItemGroups.dropFirst().flatMap(\.barButtonItems)
        #expect(originalControls.isEmpty == false)
        let group = try #require(item.trailingItemGroups.first)
        let content = try #require(group.barButtonItems.first?.customView)
        #expect(item.title == "Feed")
        #expect(item.subtitle == "17 unread")
        #expect(item.style == .browser)
        #expect(content.isDescendant(of: navigation.navigationBar))
        let hosting = try #require(content as? AppListNavigationBarBridge.RefreshHostingView)
        #expect(hosting.content.bounds.size == CGSize(width: 32, height: 32))
        #expect(item.overflowPresentationSource == nil)

        host.rootView = navigationFixture(state: .refreshing, title: "Updated Feed")
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        await nextMainQueueTurn()
        host.view.layoutIfNeeded()
        #expect(item.title == "Updated Feed")
        #expect(item.subtitle == "17 unread")
        #expect(item.style == .browser)
        #expect(item.trailingItemGroups.first === group)
        #expect(group.barButtonItems.first?.customView === content)
        #expect(content.isDescendant(of: navigation.navigationBar))
        #expect(item.additionalOverflowItems == nil)
        #expect(item.overflowPresentationSource == nil)
        #expect(item.searchController === search)
        #expect(scrollView.adjustedContentInset == initialInsets)
        #expect(scrollView.contentOffset == initialOffset)
        let updatedControls = item.trailingItemGroups.dropFirst().flatMap(\.barButtonItems)
        #expect(updatedControls.count == originalControls.count)

        host.rootView = navigationFixture(state: .idle, title: "Updated Feed")
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        await nextMainQueueTurn()
        host.view.layoutIfNeeded()
        #expect(item.trailingItemGroups.first === group)
        #expect(scrollView.adjustedContentInset == initialInsets)
        #expect(scrollView.contentOffset == initialOffset)
    }

    @Test(arguments: [375.0, 402.0])
    func idleIndicatorDoesNotTruncateCompactRussianSubtitle(width: Double) async throws {
        let sidebar = UIViewController()
        sidebar.navigationItem.backButtonDisplayMode = .minimal
        let articles = UIViewController()
        articles.navigationItem.style = .browser
        articles.navigationItem.title = "Код"
        articles.navigationItem.subtitle = "5 непрочитанных"
        articles.navigationItem.largeTitleDisplayMode = .never
        let navigation = UINavigationController(rootViewController: sidebar)
        navigation.setViewControllers([sidebar, articles], animated: false)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 874))
        window.rootViewController = navigation
        window.isHidden = false
        defer { window.isHidden = true }
        navigation.view.layoutIfNeeded()
        await nextMainQueueTurn()
        navigation.view.layoutIfNeeded()
        let baseline = try #require(visibleSubviews(in: navigation.navigationBar)
            .compactMap { $0 as? UILabel }.first { $0.text == "5 непрочитанных" })
        let baselineWidth = baseline.bounds.width
        #expect(baselineWidth + 0.5 >= baseline.intrinsicContentSize.width)

        let bridge = attachBridge(to: articles)
        defer { bridge.detach() }
        for state: AppRefreshIndicatorState in [.idle, .pulling(progress: 0.5), .idle, .refreshing, .idle] {
            bridge.updateRefreshState(state)
            bridge.install()
            navigation.view.setNeedsLayout()
            navigation.view.layoutIfNeeded()
            await nextMainQueueTurn()
            navigation.view.layoutIfNeeded()
            let group = try #require(articles.navigationItem.trailingItemGroups.first)
            #expect(group.isHidden == !state.isVisible)
            if state == .idle {
                let subtitle = try #require(visibleSubviews(in: navigation.navigationBar)
                    .compactMap { $0 as? UILabel }.first { $0.text == "5 непрочитанных" })
                #expect(abs(subtitle.bounds.width - baselineWidth) < 0.5)
                #expect(subtitle.bounds.width + 0.5 >= subtitle.intrinsicContentSize.width)
                #expect(articles.navigationItem.overflowPresentationSource == nil)
            }
        }
    }

    private func navigationFixture(state: AppRefreshIndicatorState, title: String) -> some View {
        NavigationStack {
            List { Text("Article") }
                .appListNavigationBar(title: title, subtitle: "17 unread", refreshState: state)
                .searchable(text: .constant(""), placement: .toolbar)
                .searchToolbarBehavior(.automatic)
                .toolbar {
                    DefaultToolbarItem(kind: .search, placement: .bottomBar)
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Add", systemImage: "plus", action: {})
                    }
                }
        }
    }

    private func visibleSubviews(in view: UIView) -> [UIView] {
        guard view.isHidden == false, view.alpha > 0.01 else { return [] }
        return [view] + view.subviews.flatMap { visibleSubviews(in: $0) }
    }

    private func navigationController(in controller: UIViewController) -> UINavigationController? {
        if let navigation = controller as? UINavigationController { return navigation }
        for child in controller.children {
            if let navigation = navigationController(in: child) { return navigation }
        }
        return nil
    }

    private func attachBridge(to screen: UIViewController) -> AppListNavigationBarBridge.Controller {
        let bridge = AppListNavigationBarBridge.Controller()
        screen.addChild(bridge)
        bridge.didMove(toParent: screen)
        bridge.install()
        return bridge
    }

    private func nextMainQueueTurn() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}

@Suite("Shell / Refresh Pull Gesture")
struct AppRefreshPullGestureTests {
    @Test
    func usesAdjustedTopInsetAndOneThresholdForBothScreens() {
        var state = AppRefreshPullGestureState()
        #expect(sample(&state, .began, offset: -100).progress == 0)
        #expect(sample(&state, .changed, offset: -136).progress == 0.5)
        #expect(sample(&state, .changed, offset: -172).progress == 1)
        #expect(sample(&state, .ended, offset: -172).shouldRefresh)
        #expect(sample(&state, .ended, offset: -172).shouldRefresh == false)
        #expect(sample(&state, .changed, offset: -172).shouldRefresh == false)
    }

    @Test
    func insufficientPullAndPullRetractedBeforeReleaseReturnToIdle() {
        var state = AppRefreshPullGestureState()
        _ = sample(&state, .began)
        let insufficient = sample(&state, .ended, offset: -171)
        #expect(insufficient.progress == 0)
        #expect(insufficient.shouldRefresh == false)
        _ = sample(&state, .began)
        _ = sample(&state, .changed, offset: -190)
        let retracted = sample(&state, .ended, offset: -110)
        #expect(retracted.progress == 0)
        #expect(retracted.shouldRefresh == false)
    }

    @Test
    func cancellationAndLayoutUpdatesCannotReleaseAnArmedPull() {
        var state = AppRefreshPullGestureState()
        #expect(sample(&state, .changed, offset: -190).progress == 0)
        _ = sample(&state, .began)
        _ = sample(&state, .changed, offset: -190)
        let cancelled = sample(&state, .cancelled, offset: -190)
        #expect(cancelled.progress == 0)
        #expect(cancelled.shouldRefresh == false)
        #expect(sample(&state, .ended, offset: -190).shouldRefresh == false)
        _ = sample(&state, .began)
        state.cancel() // Disappearance / scroll-view replacement.
        #expect(sample(&state, .ended, offset: -190).shouldRefresh == false)
    }

    @Test
    func busyPullCannotBecomeAnotherRefreshWhenOperationCompletes() {
        var state = AppRefreshPullGestureState()
        _ = sample(&state, .began, enabled: false)
        _ = sample(&state, .changed, offset: -190, enabled: false)
        #expect(sample(&state, .ended, offset: -190).shouldRefresh == false)
        _ = sample(&state, .began)
        #expect(sample(&state, .ended, offset: -190).shouldRefresh)
        _ = sample(&state, .began, enabled: false)
        #expect(sample(&state, .ended, offset: -190, enabled: false).shouldRefresh == false)
        _ = sample(&state, .began)
        #expect(sample(&state, .ended, offset: -190).shouldRefresh)
    }

    private func sample(
        _ state: inout AppRefreshPullGestureState,
        _ event: AppRefreshPullGestureState.Event,
        offset: CGFloat = -100,
        enabled: Bool = true
    ) -> AppRefreshPullGestureState.Result {
        state.handle(event, contentOffsetY: offset, contentInsetTop: 100, isEnabled: enabled)
    }
}
