import SwiftUI
import Testing
import UIKit
@testable import RSSReader

@Suite("Shell / List Navigation Bar")
@MainActor
struct AppListNavigationBarTests {
    @Test
    func configuresOwnNavigationItemWhileReaderIsOnTop() {
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
        let bridge = AppListNavigationBarBridge.Controller()
        list.addChild(bridge)
        bridge.didMove(toParent: list)
        bridge.install()

        #expect(list.navigationItem.style == .browser)
        #expect(list.navigationItem.title == "Feed")
        #expect(list.navigationItem.subtitle == "17 unread")
        #expect(list.navigationItem.largeTitleDisplayMode == .always)
        #expect(list.navigationItem.searchController === search)
        #expect(list.navigationItem.leftBarButtonItem === settings)
        #expect(list.navigationItem.rightBarButtonItem === filter)
        #expect(list.navigationItem.centerItemGroups.isEmpty)
        #expect(reader.navigationItem.style == .navigator)
        #expect(reader.navigationItem.centerItemGroups.isEmpty)
        #expect(navigation.topViewController === reader)
        bridge.detach()
    }

    @Test
    func suppressesUnusedOverflowProviderAndReconcilesToolbarUpdates() {
        let screen = UIViewController()
        let navigation = UINavigationController(rootViewController: screen)
        let emptyMenu = UIDeferredMenuElement { completion in completion([]) }
        screen.navigationItem.additionalOverflowItems = emptyMenu
        let bridge = AppListNavigationBarBridge.Controller()
        screen.addChild(bridge)
        bridge.didMove(toParent: screen)
        bridge.install()
        #expect(screen.navigationItem.additionalOverflowItems == nil)
        #expect(screen.navigationItem.centerItemGroups.isEmpty)

        // SwiftUI can supply a fresh deferred menu while reconciling its toolbar.
        let rebuiltMenu = UIDeferredMenuElement { completion in completion([]) }
        screen.navigationItem.additionalOverflowItems = rebuiltMenu
        bridge.install()
        bridge.install()
        #expect(screen.navigationItem.additionalOverflowItems == nil)
        #expect(screen.navigationItem.centerItemGroups.isEmpty)
        bridge.detach()
        #expect(screen.navigationItem.style == .navigator)
        #expect(screen.navigationItem.additionalOverflowItems === rebuiltMenu)
        bridge.install()
        #expect(screen.navigationItem.style == .navigator)
        #expect(navigation.topViewController === screen)
    }

    @Test
    func reparentingRestoresOldItemWithoutAddingCenterItems() {
        let first = UIViewController()
        let second = UIViewController()
        let navigation = UINavigationController(rootViewController: first)
        navigation.setViewControllers([first, second], animated: false)
        let originalMenu = UIDeferredMenuElement { completion in completion([]) }
        first.navigationItem.additionalOverflowItems = originalMenu
        let bridge = AppListNavigationBarBridge.Controller()
        first.addChild(bridge)
        bridge.didMove(toParent: first)
        bridge.install()

        bridge.willMove(toParent: nil)
        bridge.removeFromParent()
        second.addChild(bridge)
        bridge.didMove(toParent: second)
        bridge.install()
        #expect(first.navigationItem.style == .navigator)
        #expect(first.navigationItem.additionalOverflowItems === originalMenu)
        #expect(first.navigationItem.centerItemGroups.isEmpty)
        #expect(second.navigationItem.style == .browser)
        #expect(second.navigationItem.centerItemGroups.isEmpty)
        bridge.detach()
        #expect(second.navigationItem.style == .navigator)
    }

    @Test
    func teardownPreservesConfigurationAndItemsFromAnotherOwner() {
        let screen = UIViewController()
        let navigation = UINavigationController(rootViewController: screen)
        let bridge = AppListNavigationBarBridge.Controller()
        screen.addChild(bridge)
        bridge.didMove(toParent: screen)
        bridge.install()
        let foreignMenu = UIDeferredMenuElement { completion in completion([]) }
        let foreignGroup = UIBarButtonItemGroup(
            barButtonItems: [UIBarButtonItem(title: "Other", primaryAction: nil)],
            representativeItem: nil
        )
        screen.navigationItem.style = .editor
        screen.navigationItem.additionalOverflowItems = foreignMenu
        screen.navigationItem.centerItemGroups = [foreignGroup]
        bridge.detach()
        #expect(screen.navigationItem.style == .editor)
        #expect(screen.navigationItem.additionalOverflowItems === foreignMenu)
        #expect(screen.navigationItem.centerItemGroups.first === foreignGroup)
        #expect(navigation.topViewController === screen)
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
