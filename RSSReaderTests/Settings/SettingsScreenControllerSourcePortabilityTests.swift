import Foundation
import Testing
@testable import RSSReader

@Suite("Settings Screen / Controller / Source Portability")
@MainActor
struct SettingsScreenControllerSourcePortabilityTests {
    @Test
    func settingsScreenControllerPreviewsAndImportsOPMLWithoutChangingSettings() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let settingsService = try #require(harness.dependencies.appSettingsService)
        let controller = SettingsScreenController()
        let appState = AppState()
        let initialSnapshot = try settingsService.fetchSettings()
        let sidebarReloadID = appState.sourcesSidebarReloadID
        let articleListReloadID = appState.articleListReloadID
        let data = Data(
            """
            <opml version="2.0">
              <body>
                <outline text="Tech">
                  <outline text="Swift Blog" xmlUrl="https://swift.org/blog/feed.xml" />
                </outline>
              </body>
            </opml>
            """.utf8
        )

        controller.prepareOPMLImportPreview(
            data: data,
            dependencies: harness.dependencies
        )

        let preview = try #require(controller.screenState.opmlImportPreview)
        #expect(preview.importableEntryCount == 1)
        #expect(preview.createdFolderCount == 1)

        controller.commitOPMLImportPreview(
            dependencies: harness.dependencies,
            appState: appState
        )

        let status = try #require(controller.screenState.opmlTransferStatus)
        let feed = try #require(try harness.feedRepository.fetchFeed(url: "https://swift.org/blog/feed.xml"))
        #expect(status.title == SettingsLocalization.opmlImportCompleteTitle)
        #expect(feed.displayTitle == "Swift Blog")
        #expect(feed.folder?.name == "Tech")
        #expect(appState.sourcesSidebarReloadID != sidebarReloadID)
        #expect(appState.articleListReloadID != articleListReloadID)
        #expect(try settingsService.fetchSettings() == initialSnapshot)
    }

    @Test
    func settingsScreenControllerBuildsOPMLExportDocumentFromRepositories() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let controller = SettingsScreenController()
        _ = try harness.feedRepository.insert(
            Feed(
                url: "https://example.com/feed.xml",
                siteURL: "https://example.com/",
                title: "Example Feed",
                kind: .rss
            )
        )

        let document = try #require(
            controller.makeOPMLExportDocument(dependencies: harness.dependencies)
        )

        #expect(document.xml.contains(#"<opml version="2.0">"#))
        #expect(document.xml.contains(#"xmlUrl="https://example.com/feed.xml""#))
        #expect(document.xml.contains(#"htmlUrl="https://example.com/""#))
    }

    @Test
    func settingsScreenControllerShowsImportFailureForMalformedOPML() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let controller = SettingsScreenController()

        controller.prepareOPMLImportPreview(
            data: Data("<opml><body></opml>".utf8),
            dependencies: harness.dependencies
        )

        #expect(controller.screenState.opmlImportPreview == nil)
        #expect(controller.screenState.opmlTransferStatus == SettingsOPMLTransferStatusPresentation(
            title: SettingsLocalization.opmlImportFailedTitle,
            message: SettingsLocalization.selectedFileInvalidXMLMessage,
            kind: .failure
        ))
    }
}
