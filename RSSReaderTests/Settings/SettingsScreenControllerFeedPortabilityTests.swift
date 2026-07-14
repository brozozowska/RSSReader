import Foundation
import Testing
@testable import RSSReader

@Suite("Settings Screen / Controller / Feed Portability")
@MainActor
struct SettingsScreenControllerFeedPortabilityTests {
    @Test
    func settingsScreenControllerPreviewsAndImportsOPMLWithoutChangingSettings() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let settingsService = try #require(harness.dependencies.appSettingsService)
        let controller = SettingsScreenController()
        let appState = AppState()
        let initialSnapshot = try settingsService.fetchSettings()
        let sidebarReloadID = appState.sidebarReloadID
        let articleListReloadID = appState.articleListReloadID
        let fileURL = try makeTemporaryFile(data: Data(
            """
            <opml version="2.0">
              <body>
                <outline text="Tech">
                  <outline text="Swift Blog" xmlUrl="https://swift.org/blog/feed.xml" />
                </outline>
              </body>
            </opml>
            """.utf8
        ))
        defer { try? FileManager.default.removeItem(at: fileURL) }

        await controller.prepareOPMLImportPreview(
            fileURL: fileURL,
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
        #expect(appState.sidebarReloadID != sidebarReloadID)
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
    func settingsScreenControllerShowsImportFailureForMalformedOPML() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let controller = SettingsScreenController()
        let fileURL = try makeTemporaryFile(data: Data("<opml><body></opml>".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }

        await controller.prepareOPMLImportPreview(
            fileURL: fileURL,
            dependencies: harness.dependencies
        )

        #expect(controller.screenState.opmlImportPreview == nil)
        #expect(controller.screenState.opmlTransferStatus == SettingsOPMLTransferStatusPresentation(
            title: SettingsLocalization.opmlImportFailedTitle,
            message: SettingsLocalization.selectedFileInvalidXMLMessage,
            kind: .failure
        ))
    }

    @Test
    func settingsScreenControllerShowsDedicatedFailureForOversizedOPML() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let controller = SettingsScreenController()
        let maximumBytes = 64
        let fileURL = try makeTemporaryFile(
            data: Data(repeating: 0x20, count: maximumBytes + 1)
        )
        defer { try? FileManager.default.removeItem(at: fileURL) }

        await controller.prepareOPMLImportPreview(
            fileURL: fileURL,
            dependencies: harness.dependencies,
            fileLoader: makeLoader(maximumBytes: maximumBytes)
        )

        #expect(controller.screenState.opmlImportPreview == nil)
        #expect(controller.screenState.opmlTransferStatus == SettingsOPMLTransferStatusPresentation(
            title: SettingsLocalization.opmlImportFailedTitle,
            message: SettingsLocalization.selectedFileTooLargeMessage,
            kind: .failure
        ))
    }

    @Test
    func settingsScreenControllerIgnoresCancellationWithoutLoggingFailureStatus() async throws {
        let logger = RecordingLogger()
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(),
            logger: logger
        )
        let controller = SettingsScreenController()
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("opml")

        let task = Task {
            await controller.prepareOPMLImportPreview(
                fileURL: fileURL,
                dependencies: harness.dependencies,
                fileLoader: SuspendedOPMLImportFileLoader()
            )
        }
        await Task.yield()
        task.cancel()
        await task.value

        #expect(controller.screenState.opmlImportPreview == nil)
        #expect(controller.screenState.opmlTransferStatus == nil)
        #expect(logger.entries.isEmpty)
    }

    private func makeLoader(maximumBytes: Int) -> BoundedOPMLImportFileLoader {
        BoundedOPMLImportFileLoader(
            budget: RuntimeXMLInputBudget(
                body: RuntimeInputBodyBudget(
                    input: .opml,
                    maximumCompressedBodyBytes: Int64(maximumBytes),
                    allowedMIMETypes: ["application/xml"]
                ),
                maximumElementCount: 100,
                maximumDepth: 10,
                maximumEntryCount: 10
            )
        )
    }

    private func makeTemporaryFile(data: Data) throws -> URL {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("opml")
        try data.write(to: fileURL)
        return fileURL
    }
}

private nonisolated struct SuspendedOPMLImportFileLoader: OPMLImportFileLoading {
    func loadPreview(
        fileURL: URL,
        existingFeeds: [FeedManagementFeedSummary],
        existingFolders: [FeedManagementFolderSummary]
    ) async throws -> OPMLImportPreviewPlan {
        try await Task.sleep(for: .seconds(60))
        throw CancellationError()
    }
}
