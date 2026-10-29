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

    func testOPMLPickerCancelPreservesDraftUntilApply() {
        tap(element("sidebar.settings"))
        let apply = app.buttons["Apply Settings"]
        expect(apply)
        XCTAssertFalse(apply.isEnabled)
        let draftSwitch = app.switches.firstMatch
        let control = draftSwitch.switches.firstMatch
        tap(control.exists ? control : draftSwitch)
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: apply)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 10), .completed, app.debugDescription)

        for title in ["Export OPML", "Import OPML"] {
            let action = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
            for _ in 0..<6 {
                if action.exists && action.isHittable { break }
                element("settings.list").swipeUp()
            }
            tap(action)
            let pickerBar = app.navigationBars["FullDocumentManagerViewControllerNavigationBar"]
            expect(pickerBar)
            let cancel = app.navigationBars.buttons.matching(
                NSPredicate(format: "label IN %@", ["Cancel", "Отменить", "Отмена"])
            ).firstMatch
            // Files can restore a nested location. Browse exposes native Cancel.
            if cancel.exists == false {
                tap(pickerBar.buttons["BackButton"])
            }
            tap(cancel)
            expectAbsent(app.navigationBars["FullDocumentManagerViewControllerNavigationBar"])
            if app.alerts.firstMatch.exists {
                tap(app.alerts.firstMatch.buttons.firstMatch)
            }
            XCTAssertTrue(apply.isEnabled, "Picker cancellation must retain the Settings draft")
        }
        tap(apply)
        expectAbsent(element("settings.close"))
        tap(element("sidebar.settings"))
        expect(apply)
        XCTAssertFalse(apply.isEnabled)
        tap(element("settings.close"))
    }

    func testRelaunchStartsWithFreshFixtures() {
        openFixtureArticle()
        app.terminate()
        app.launch()
        expect(element(feedID))
        expectAbsent(element(readerID))
        openFixtureArticle()
    }

    func testFeedSaveInitialRefreshRenameAndUnsubscribe() {
        expect(element(feedID))
        tap(app.buttons["Add Feed"].firstMatch)
        tap(app.collectionViews.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Add Feed")).firstMatch)
        let url = app.textFields["example.com"]
        tap(url)
        url.typeText("https://ui-smoke.invalid/added-feed\n")
        expect(app.staticTexts["Added Smoke Feed"].firstMatch)
        tap(app.navigationBars["Add Feed"].buttons["Add Feed"])
        let added = app.staticTexts["Added Smoke Feed"].firstMatch
        expect(added)
        tap(added)
        expect(app.staticTexts["Added Smoke Article"].firstMatch)
        if !isPad {
            tap(app.navigationBars.buttons.matching(identifier: "BackButton").firstMatch)
        }

        expect(added)
        pressSidebarRow(containing: added)
        tap(app.buttons["Rename..."])
        replaceText(in: app.textFields.firstMatch, with: "Renamed Smoke Feed")
        tap(app.buttons["Save Changes"])
        let renamed = app.staticTexts["Renamed Smoke Feed"].firstMatch
        expect(renamed)

        pressSidebarRow(containing: renamed)
        tap(app.buttons["Unsubscribe"])
        tap(app.alerts.buttons["Cancel"])
        expect(renamed)
        pressSidebarRow(containing: renamed)
        tap(app.buttons["Unsubscribe"])
        tap(app.alerts.buttons["Unsubscribe"])
        expectAbsent(renamed)
        expect(element(feedID))
    }

    func testFolderCreateRenameMoveAndDelete() {
        expect(element(feedID))
        tap(app.buttons["Add Feed"].firstMatch)
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Create Folder")).firstMatch)
        replaceText(in: app.textFields.firstMatch, with: "Smoke Folder")
        tap(app.navigationBars.buttons["Create Folder"])
        tap(app.navigationBars.buttons.matching(identifier: "BackButton").firstMatch)
        tap(app.buttons["Close Manage Feeds"])
        let folder = app.buttons["Smoke Folder"].firstMatch
        expect(folder)
        pressSidebarRow(containing: folder, type: .button)
        tap(app.buttons["Rename..."])
        replaceText(in: app.textFields.firstMatch, with: "Renamed Smoke Folder")
        tap(app.buttons["Save Folder"])

        pressSidebarRow(containing: element(feedID))
        tap(app.buttons["Organize..."])
        let placement = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Renamed Smoke Folder,")
        ).firstMatch
        expect(placement)
        // Plain SwiftUI buttons do not hit-test the empty Spacer on wide iPad rows.
        tap(placement.staticTexts["Renamed Smoke Folder"])
        let move = app.navigationBars.buttons["Move Feed"]
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: move)
        guard XCTWaiter.wait(for: [enabled], timeout: 10) == .completed else {
            attachFailureScreenshot()
            XCTFail("Expected enabled Move Feed\n\(app.debugDescription)")
            return
        }
        tap(move)
        expectAbsent(app.navigationBars["Move Feed"])
        expect(element(feedID))

        let folderRow = app.cells.containing(
            .button, identifier: "Renamed Smoke Folder"
        ).firstMatch
        tap(folderRow.buttons["chevron.down"])
        expectAbsent(element(feedID))
        tap(folderRow.buttons["chevron.right"])
        expect(element(feedID))

        let renamedFolder = app.buttons["Renamed Smoke Folder"].firstMatch
        expect(renamedFolder)
        pressSidebarRow(containing: renamedFolder, type: .button)
        tap(app.buttons["Delete"])
        tap(app.alerts.buttons["Delete Folder"])
        expectAbsent(renamedFolder)
        // Deleting a folder keeps its feed as an ungrouped subscription.
        expect(element(feedID))
    }

    private func pressSidebarRow(containing text: XCUIElement, type: XCUIElement.ElementType = .staticText) {
        let identifier = text.identifier.isEmpty ? text.label : text.identifier
        let row = app.cells.containing(
            type, identifier: identifier
        ).firstMatch
        expect(row)
        row.press(forDuration: 1)
    }

    private func replaceText(in field: XCUIElement, with value: String) {
        tap(field)
        let current = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count) + value)
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
        guard XCTWaiter.wait(for: [hittable], timeout: 10) == .completed else {
            attachFailureScreenshot()
            XCTFail("Expected hittable \(element)\n\(app.debugDescription)", file: file, line: line)
            return
        }
        element.tap()
    }

    private func attachFailureScreenshot() {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
