import Foundation
import Testing
@testable import RSSReader

@Suite("Feed Management / Add Feed State")
@MainActor
struct FeedManagementAddFeedStateTests {
    @Test
    func addFeedStateBuildsPreviewCommandAndCreationCommand() {
        var state = FeedManagementAddFeedState()
        let folderID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

        state.applyAvailableFolders([
            FeedManagementFolderSummary(
                id: folderID,
                name: "Tech",
                sortOrder: 0,
                feedCount: 2
            )
        ])
        state.updateURLInput(" example.com/feed.xml ")
        state.selectFolderPlacement(.folder(folderID))

        let previewCommand = state.beginPreviewLoading()
        #expect(previewCommand?.urlString == "https://example.com/feed.xml")

        if let previewCommand {
            state.applyLoadedPreview(
                FeedManagementFeedPreview(
                    requestedURL: previewCommand.urlString,
                    resolvedFeedURL: previewCommand.urlString,
                    title: "Example Feed",
                    subtitle: nil,
                    siteURL: "https://example.com/",
                    iconURL: nil,
                    language: "en",
                    kind: .rss,
                    parserAnomalyCount: 0,
                    rejectedEntryCount: 0,
                    existingFeedID: nil
                ),
                command: previewCommand
            )
        }

        let createCommand = state.beginFeedCreation()
        #expect(createCommand?.folderPlacement == .folder(folderID))
        #expect(createCommand?.displayTitleOverride == nil)
    }

    @Test
    func editFeedStateIgnoresURLChangesAndBuildsRenameOnlyUpdateCommand() {
        var state = FeedManagementAddFeedState()
        let feedID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let initialFeed = FeedManagementFeedSummary(
            id: feedID,
            url: "https://example.com/original.xml",
            title: "Original Feed",
            folderID: nil,
            folderName: nil
        )

        state.applyEditingFeed(initialFeed)
        state.updateURLInput("https://example.com")
        state.updateDisplayNameInput("Renamed Feed")
        let presentation = state.derivedPresentation()

        #expect(presentation.title == FeedManagementLocalization.renameFeedTitle)
        #expect(presentation.showsSummary == false)
        #expect(presentation.showsURLInput == false)
        #expect(presentation.showsDisplayNameInput)
        #expect(presentation.allowsPreviewAction == false)
        #expect(presentation.placementOptions.isEmpty)
        #expect(presentation.createFolderActionTitle == nil)
        #expect(state.beginPreviewLoading() == nil)
        #expect(state.shouldPreviewBeforeSaving() == false)

        let updateCommand = state.beginFeedUpdate()
        #expect(updateCommand?.feedID == feedID)
        #expect(updateCommand?.preview == nil)
        #expect(updateCommand?.displayTitleOverride == "Renamed Feed")
    }
}
