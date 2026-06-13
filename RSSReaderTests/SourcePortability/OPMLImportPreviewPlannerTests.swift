import Foundation
import Testing
@testable import RSSReader

@Suite("Source Portability / OPML Import Preview Planner")
@MainActor
struct OPMLImportPreviewPlannerTests {
    @Test
    func buildsPreviewEntriesWithNormalizedValuesAndFolderResolution() {
        let existingFolderID = UUID()
        let document = OPMLDocumentDTO(
            version: "2.0",
            title: "Sources",
            feeds: [
                OPMLFeedOutlineDTO(
                    folderPath: [" Tech ", " Apple "],
                    title: " Swift Blog ",
                    text: nil,
                    xmlURL: " HTTPS://Swift.org:443/blog/feed.xml#latest ",
                    htmlURL: nil
                ),
                OPMLFeedOutlineDTO(
                    folderPath: [" Existing "],
                    title: nil,
                    text: " Existing Folder Feed ",
                    xmlURL: "https://example.com/rss",
                    htmlURL: nil
                ),
                OPMLFeedOutlineDTO(
                    folderPath: [],
                    title: "Ungrouped",
                    text: nil,
                    xmlURL: "https://example.com/ungrouped",
                    htmlURL: nil
                )
            ],
            ignoredOutlineCount: 2
        )

        let plan = OPMLImportPreviewPlanner.makePlan(
            document: document,
            existingFeeds: [],
            existingFolders: [
                SourceManagementFolderSummary(
                    id: existingFolderID,
                    name: "Existing",
                    sortOrder: 0,
                    feedCount: 1
                )
            ]
        )

        #expect(plan.ignoredOutlineCount == 2)
        #expect(plan.importableEntries.count == 3)
        #expect(plan.invalidEntryCount == 0)
        #expect(plan.entries[0].normalizedFeedURL == "https://swift.org/blog/feed.xml")
        #expect(plan.entries[0].displayTitle == "Swift Blog")
        #expect(plan.entries[0].normalizedFolderName == "Tech / Apple")
        #expect(plan.entries[0].folderResolution == .newFolder(name: "Tech / Apple"))
        #expect(plan.entries[1].folderResolution == .existingFolder(id: existingFolderID, name: "Existing"))
        #expect(plan.entries[2].folderResolution == .ungrouped)
    }

    @Test
    func marksInvalidFeedURLsWithoutDroppingEntries() {
        let document = OPMLDocumentDTO(
            version: "2.0",
            title: nil,
            feeds: [
                OPMLFeedOutlineDTO(
                    folderPath: [],
                    title: nil,
                    text: nil,
                    xmlURL: "not a feed url",
                    htmlURL: nil
                )
            ],
            ignoredOutlineCount: 0
        )

        let plan = OPMLImportPreviewPlanner.makePlan(
            document: document,
            existingFeeds: [],
            existingFolders: []
        )

        let entry = plan.entries[0]
        #expect(entry.normalizedFeedURL == nil)
        #expect(entry.displayTitle == "not a feed url")
        #expect(entry.issues == [.invalidFeedURL("not a feed url")])
        #expect(entry.isImportable == false)
    }

    @Test
    func marksDuplicateFeedURLAgainstExistingFeedsAndEarlierImportedEntries() {
        let existingFeedID = UUID()
        let document = OPMLDocumentDTO(
            version: "2.0",
            title: nil,
            feeds: [
                OPMLFeedOutlineDTO(
                    folderPath: [],
                    title: "Existing URL",
                    text: nil,
                    xmlURL: "https://example.com/feed.xml",
                    htmlURL: nil
                ),
                OPMLFeedOutlineDTO(
                    folderPath: [],
                    title: "First Import",
                    text: nil,
                    xmlURL: "https://new.example.com/feed.xml#fragment",
                    htmlURL: nil
                ),
                OPMLFeedOutlineDTO(
                    folderPath: [],
                    title: "Second Import",
                    text: nil,
                    xmlURL: "https://NEW.example.com/feed.xml",
                    htmlURL: nil
                )
            ],
            ignoredOutlineCount: 0
        )

        let plan = OPMLImportPreviewPlanner.makePlan(
            document: document,
            existingFeeds: [
                SourceManagementFeedSummary(
                    id: existingFeedID,
                    url: "https://example.com/feed.xml",
                    title: "Already Saved",
                    folderID: nil,
                    folderName: nil
                )
            ],
            existingFolders: []
        )

        #expect(plan.entries[0].issues == [
            .duplicateFeedURL("https://example.com/feed.xml", source: .existingFeed(id: existingFeedID))
        ])
        #expect(plan.entries[1].issues.isEmpty)
        #expect(plan.entries[2].issues == [
            .duplicateFeedURL("https://new.example.com/feed.xml", source: .importedEntry(index: 1))
        ])
    }

    @Test
    func marksDuplicateDisplayTitleAgainstExistingFeedsAndEarlierImportedEntries() {
        let existingFeedID = UUID()
        let document = OPMLDocumentDTO(
            version: "2.0",
            title: nil,
            feeds: [
                OPMLFeedOutlineDTO(
                    folderPath: [],
                    title: "Saved Title",
                    text: nil,
                    xmlURL: "https://example.com/one.xml",
                    htmlURL: nil
                ),
                OPMLFeedOutlineDTO(
                    folderPath: [],
                    title: "Unique Title",
                    text: nil,
                    xmlURL: "https://example.com/two.xml",
                    htmlURL: nil
                ),
                OPMLFeedOutlineDTO(
                    folderPath: [],
                    title: "unique title",
                    text: nil,
                    xmlURL: "https://example.com/three.xml",
                    htmlURL: nil
                )
            ],
            ignoredOutlineCount: 0
        )

        let plan = OPMLImportPreviewPlanner.makePlan(
            document: document,
            existingFeeds: [
                SourceManagementFeedSummary(
                    id: existingFeedID,
                    url: "https://saved.example.com/rss",
                    title: "saved title",
                    folderID: nil,
                    folderName: nil
                )
            ],
            existingFolders: []
        )

        #expect(plan.entries[0].issues == [
            .duplicateDisplayTitle("Saved Title", source: .existingFeed(id: existingFeedID))
        ])
        #expect(plan.entries[1].issues.isEmpty)
        #expect(plan.entries[2].issues == [
            .duplicateDisplayTitle("unique title", source: .importedEntry(index: 1))
        ])
    }
}
