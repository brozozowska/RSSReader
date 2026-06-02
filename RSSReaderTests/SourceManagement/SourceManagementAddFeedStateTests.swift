import Foundation
import Testing
@testable import RSSReader

@Suite("Source Management / Add Feed State")
@MainActor
struct SourceManagementAddFeedStateTests {
    @Test
    func addFeedStateBuildsPreviewCommandAndCreationCommand() {
        var state = SourceManagementAddFeedState()
        let folderID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

        state.applyAvailableFolders([
            SourceManagementFolderSummary(
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
                SourceManagementFeedPreview(
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
}
