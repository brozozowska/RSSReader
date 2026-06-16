import Foundation
import Testing
@testable import RSSReader

@Suite("Source Portability / OPML Import Persistence")
@MainActor
struct OPMLImportPersistenceServiceTests {
    @Test
    func importsValidPreviewEntriesThroughFeedManagementServiceAndSkipsInvalidEntries() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let service = try #require(harness.dependencies.feedManagementService)
        let existingFeed = try #require(
            try harness.insertFeeds(urls: ["https://example.com/existing.xml"]).first
        )
        _ = try harness.feedRepository.updateDetails(
            for: existingFeed.id,
            with: FeedDetailsUpdate(displayTitleOverride: "Existing Title")
        )
        let existingFolder = try service.createFolder(
            FeedManagementCreateFolderCommand(name: "Saved Folder")
        )
        let document = OPMLDocumentDTO(
            version: "2.0",
            title: "Imported Sources",
            feeds: [
                OPMLFeedOutlineDTO(
                    folderPath: ["New", "Folder"],
                    title: "New Feed",
                    text: nil,
                    xmlURL: "https://example.com/new.xml",
                    htmlURL: "https://example.com/"
                ),
                OPMLFeedOutlineDTO(
                    folderPath: ["New", "Folder"],
                    title: "Second Feed",
                    text: nil,
                    xmlURL: "https://example.com/second.xml",
                    htmlURL: nil
                ),
                OPMLFeedOutlineDTO(
                    folderPath: ["Saved Folder"],
                    title: "Grouped Feed",
                    text: nil,
                    xmlURL: "https://example.com/grouped.xml",
                    htmlURL: nil
                ),
                OPMLFeedOutlineDTO(
                    folderPath: [],
                    title: "Existing URL",
                    text: nil,
                    xmlURL: "https://example.com/existing.xml",
                    htmlURL: nil
                ),
                OPMLFeedOutlineDTO(
                    folderPath: [],
                    title: "Invalid URL",
                    text: nil,
                    xmlURL: "not a feed url",
                    htmlURL: nil
                )
            ],
            ignoredOutlineCount: 1
        )
        let plan = try OPMLImportPreviewPlanner.makePlan(
            document: document,
            feedManagementService: service
        )

        let result = try OPMLImportPersistenceService.importPreview(
            plan,
            feedManagementService: service,
            importedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        #expect(result.createdFolderCount == 1)
        #expect(result.createdFolders.map(\.name) == ["New / Folder"])
        #expect(result.createdFeedCount == 3)
        #expect(result.skippedEntryCount == 2)
        #expect(result.skippedEntries.map(\.entryID) == [3, 4])

        let persistedFeeds = try service.fetchFeeds()
        #expect(persistedFeeds.contains { $0.title == "New Feed" && $0.folderName == "New / Folder" })
        #expect(persistedFeeds.contains { $0.title == "Second Feed" && $0.folderName == "New / Folder" })
        #expect(persistedFeeds.contains { $0.title == "Grouped Feed" && $0.folderID == existingFolder.id })
        #expect(persistedFeeds.filter { $0.url == "https://example.com/existing.xml" }.count == 1)
    }

    @Test
    func skipsFeedManagementDuplicateRejectionsFromStalePreview() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let service = try #require(harness.dependencies.feedManagementService)
        let entry = OPMLImportPreviewEntryDTO(
            id: 0,
            outline: OPMLFeedOutlineDTO(
                folderPath: [],
                title: "Imported Feed",
                text: nil,
                xmlURL: "https://example.com/imported.xml",
                htmlURL: nil
            ),
            normalizedFeedURL: "https://example.com/imported.xml",
            displayTitle: "Imported Feed",
            normalizedFolderName: nil,
            folderResolution: .ungrouped,
            issues: []
        )
        let stalePlan = OPMLImportPreviewPlan(
            entries: [entry, entry],
            ignoredOutlineCount: 0
        )

        let result = try OPMLImportPersistenceService.importPreview(
            stalePlan,
            feedManagementService: service
        )

        #expect(result.createdFeedCount == 1)
        #expect(result.skippedEntries == [
            OPMLImportSkippedEntryDTO(
                entryID: 0,
                displayTitle: "Imported Feed",
                reason: .feedManagementRejected(
                    .duplicateFeed("https://example.com/imported.xml")
                )
            )
        ])
    }
}
