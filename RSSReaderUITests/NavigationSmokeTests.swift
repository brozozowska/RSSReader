import XCTest
import UIKit

@MainActor
final class NavigationSmokeTests: XCTestCase {
    private let feedID = "sidebar.feed.72000000-0000-0000-0000-000000000001"
    private let rowID = "articles.row.72000000-0000-0000-0000-000000000002"
    private let readerID = "reader.content.72000000-0000-0000-0000-000000000002"
    private var app: XCUIApplication!
    private var server: LoopbackArticleServer!
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    override func setUpWithError() throws {
        continueAfterFailure = false
#if !DEBUG || !targetEnvironment(simulator)
        throw NSError(domain: "RSSReaderUISmoke", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "UI smoke requires a Debug iOS Simulator build; app launch refused."
        ])
#else
        server = try LoopbackArticleServer()
        let sourceURL = try server.start()
        app = XCUIApplication()
        app.launchArguments = ["--ui-smoke", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["RSSREADER_UI_SMOKE_SOURCE_URL"] = sourceURL.absoluteString
        XCUIDevice.shared.orientation = isPad ? .landscapeLeft : .portrait
        app.launch()
#endif
    }

    override func tearDownWithError() throws {
        app?.terminate()
        server?.stop()
        XCUIDevice.shared.orientation = .portrait
    }

    func testReaderSafariAndReturnRoutes() {
        openFixtureArticle()
        tap(element("reader.openSource"))
        let safari = element("safari.browser")
        expect(safari)
        expect(app.webViews.firstMatch)
        expect(app.webViews.staticTexts["Local source article"])
        // System Safari Close retains its native delegate dismissal path.
        // Safari runs out of process and can retain the Simulator's ru locale
        // even when the app launch pins en_US. Scope to its actual browser bar.
        let close = safari.otherElements["TopBrowserBar"].buttons.matching(
            NSPredicate(format: "label IN %@", ["Close", "Закрыть"])
        ).firstMatch
        expect(close)
        // iOS 27 Safari's URL accessibility frame overlaps Close. XCTest's
        // automatic hit point lands in the rounded button's corner on iPhone.
        // Derive the native control's centre from its current semantic element;
        // no screen coordinates or screenshot estimation are involved.
        close.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        expectAbsent(safari)
        expect(element(readerID))
        if isPad {
            // Landscape regular-width navigation retains the list alongside Reader.
            expect(element("articles.list"))
            XCTAssertTrue(element(rowID).isHittable)
        } else {
            tap(app.navigationBars.buttons.matching(identifier: "BackButton").firstMatch)
            expect(element(rowID))
            tap(app.navigationBars.buttons.matching(identifier: "BackButton").firstMatch)
            expect(element(feedID))
            // Retained query context must still reopen after native Back.
            tap(element(feedID))
            expect(element(rowID))
        }
    }

    func testSettingsPresentationAndDismissal() {
        expect(element(feedID))
        tap(element("sidebar.settings"))
        let close = element("settings.close")
        expect(close)
        tap(close)
        expectAbsent(close)
        expect(element(feedID))
        tap(element("sidebar.settings"))
        tap(element("settings.close"))
        expect(element(feedID))
    }

    func testRelaunchStartsWithFreshFixtures() {
        openFixtureArticle()
        app.terminate()
        app.launch()
        expect(element(feedID))
        expectAbsent(element(readerID))
        openFixtureArticle()
    }

    private func openFixtureArticle() {
        tap(element(feedID))
        tap(element(rowID))
        expect(element(readerID))
        expect(element("reader.openSource"))
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func expect(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        guard element.waitForExistence(timeout: 10) else {
            attachFailureScreenshot()
            XCTFail("Expected \(element)\n\(app.debugDescription)", file: file, line: line)
            return
        }
    }

    private func expectAbsent(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let absent = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        guard XCTWaiter.wait(for: [absent], timeout: 10) == .completed else {
            attachFailureScreenshot()
            XCTFail("Expected disappearance of \(element)\n\(app.debugDescription)", file: file, line: line)
            return
        }
    }

    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        expect(element, file: file, line: line)
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [hittable], timeout: 10), .completed, file: file, line: line)
        element.tap()
    }

    private func attachFailureScreenshot() {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
