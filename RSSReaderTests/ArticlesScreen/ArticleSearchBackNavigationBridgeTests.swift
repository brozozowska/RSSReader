import Testing
import UIKit
@testable import RSSReader

@Suite("Articles Screen / Search Back Navigation")
@MainActor
struct ArticleSearchBackNavigationBridgeTests {
    @Test
    func activeListSearchAllowsNativeBackAndPassiveSearchDefersToUIKit() {
        let list = UIViewController()
        let navigation = UINavigationController(rootViewController: UIViewController())
        navigation.pushViewController(list, animated: false)
        let original = BackGestureDelegateStub()
        let proxy = ArticleSearchBackGestureDelegate(
            navigationController: navigation, originalDelegate: original,
            ownsTopController: { $0 === list }
        )
        let gesture = UIGestureRecognizer()
        let search = ActiveSearchController(searchResultsController: nil)
        list.navigationItem.searchController = search

        #expect(proxy.gestureRecognizerShouldBegin(gesture) == false)
        #expect(proxy.gestureRecognizer(gesture, shouldReceive: UITouch()) == false)
        search.isActive = true
        #expect(proxy.gestureRecognizerShouldBegin(gesture))
        #expect(proxy.gestureRecognizer(gesture, shouldReceive: UITouch()))
        search.isActive = false
        #expect(proxy.gestureRecognizerShouldBegin(gesture) == false)
        original.allowsBegin = true
        #expect(proxy.gestureRecognizerShouldBegin(gesture))
    }

    @Test
    func searchOverrideDoesNotApplyToReaderOrRoot() {
        let list = UIViewController()
        let navigation = UINavigationController(rootViewController: UIViewController())
        navigation.pushViewController(list, animated: false)
        let original = BackGestureDelegateStub()
        let proxy = ArticleSearchBackGestureDelegate(
            navigationController: navigation, originalDelegate: original,
            ownsTopController: { $0 === list }
        )
        let search = ActiveSearchController(searchResultsController: nil)
        list.navigationItem.searchController = search
        search.isActive = true
        navigation.pushViewController(UIViewController(), animated: false)
        #expect(proxy.gestureRecognizerShouldBegin(UIGestureRecognizer()) == false)
        navigation.popViewController(animated: false)
        navigation.setViewControllers([list], animated: false)
        #expect(proxy.gestureRecognizerShouldBegin(UIGestureRecognizer()) == false)
    }

    @Test
    func activeSearchBackRequiresSemanticHorizontalDirection() {
        let list = UIViewController()
        let navigation = UINavigationController(rootViewController: UIViewController())
        navigation.pushViewController(list, animated: false)
        let search = ActiveSearchController(searchResultsController: nil)
        search.isActive = true
        list.navigationItem.searchController = search
        let proxy = ArticleSearchBackGestureDelegate(
            navigationController: navigation, originalDelegate: nil,
            ownsTopController: { $0 === list }
        )
        let view = UIView()
        let pan = BackPanGestureStub()
        view.addGestureRecognizer(pan)
        view.semanticContentAttribute = .forceLeftToRight
        pan.nextVelocity = CGPoint(x: 100, y: 20)
        #expect(proxy.gestureRecognizerShouldBegin(pan))
        pan.nextVelocity = CGPoint(x: -100, y: 20)
        #expect(proxy.gestureRecognizerShouldBegin(pan) == false)
        pan.nextVelocity = CGPoint(x: 20, y: 100)
        #expect(proxy.gestureRecognizerShouldBegin(pan) == false)
        view.semanticContentAttribute = .forceRightToLeft
        pan.nextVelocity = CGPoint(x: -100, y: 20)
        #expect(proxy.gestureRecognizerShouldBegin(pan))
        pan.nextVelocity = CGPoint(x: 100, y: 20)
        #expect(proxy.gestureRecognizerShouldBegin(pan) == false)
    }

    @Test
    func anotherModalKeepsUIKitSearchBackVeto() {
        let list = ModalListController()
        let navigation = UINavigationController(rootViewController: UIViewController())
        navigation.pushViewController(list, animated: false)
        let search = ActiveSearchController(searchResultsController: nil)
        search.isActive = true
        list.navigationItem.searchController = search
        let original = BackGestureDelegateStub()
        let proxy = ArticleSearchBackGestureDelegate(
            navigationController: navigation, originalDelegate: original,
            ownsTopController: { $0 === list }
        )
        list.modal = UIViewController()
        #expect(proxy.gestureRecognizerShouldBegin(UIGestureRecognizer()) == false)
        #expect(proxy.gestureRecognizer(UIGestureRecognizer(), shouldReceive: UITouch()) == false)
    }

    @Test
    func bridgeRestoresUIKitDelegateWhenDisabledOrDetached() throws {
        let list = UIViewController()
        let navigation = UINavigationController(rootViewController: UIViewController())
        navigation.pushViewController(list, animated: false)
        let bridge = ArticleSearchBackNavigationBridge.BridgeController()
        list.addChild(bridge)
        list.view.addSubview(bridge.view)
        bridge.didMove(toParent: list)
        let gesture = try #require(navigation.interactivePopGestureRecognizer)
        let original = BackGestureDelegateStub()
        gesture.delegate = original
        bridge.isEnabled = true
        bridge.installIfNeeded()
        #expect(gesture.delegate is ArticleSearchBackGestureDelegate)
        bridge.installIfNeeded()
        bridge.isEnabled = false
        bridge.installIfNeeded()
        #expect(gesture.delegate === original)
        bridge.isEnabled = true
        bridge.installIfNeeded()
        bridge.detach()
        #expect(gesture.delegate === original)
    }
}

@MainActor
private final class BackPanGestureStub: UIPanGestureRecognizer {
    var nextVelocity = CGPoint.zero
    override func velocity(in view: UIView?) -> CGPoint { nextVelocity }
}

@MainActor
private final class ModalListController: UIViewController {
    var modal: UIViewController?
    override var presentedViewController: UIViewController? { modal }
}

@MainActor
private final class ActiveSearchController: UISearchController {
    private var simulatedIsActive = false
    override var isActive: Bool {
        get { simulatedIsActive }
        set { simulatedIsActive = newValue }
    }
}

@MainActor
private final class BackGestureDelegateStub: NSObject, UIGestureRecognizerDelegate {
    var allowsBegin = false

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        allowsBegin
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        false
    }
}
