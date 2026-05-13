import Foundation
import Testing
@testable import RSSReader

@Suite("Source Management / Screen State")
@MainActor
struct SourceManagementScreenStateTests {
    @Test
    func sourceManagementScreenStateBuildsSeparatedEntrySections() {
        let state = SourceManagementScreenState.makePreviewFixture()
        let viewState = state.derivedViewState()

        #expect(viewState.summary.title == "Manage sources and folders.")
        #expect(viewState.sections.map(\.id) == [.startNew, .organizeExisting])
        #expect(viewState.sections.first?.items.map(\.id) == [.addFeed, .createFolder])
        #expect(viewState.sections.last?.items.map(\.id) == [.moveSource])
    }

    @Test
    func sourceManagementScreenStateBuildsAddFeedPresentationWithPreviewAndConfirmationState() {
        var state = SourceManagementScreenState.makePreviewFixture()
        let newsFolderID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let techFolderID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        state.applyAddFeedFolderContext(
            folders: [
                SourceManagementFolderSummary(
                    id: newsFolderID,
                    name: "News",
                    sortOrder: 0,
                    feedCount: 5
                ),
                SourceManagementFolderSummary(
                    id: techFolderID,
                    name: "Tech",
                    sortOrder: 1,
                    feedCount: 3
                )
            ]
        )
        state.presentScenario(.addFeed)

        guard case .addFeed(let initialDestination)? = state.derivedViewState().presentedDestination else {
            Issue.record("Expected add-feed destination presentation")
            return
        }

        #expect(initialDestination.validationMessage == "Enter a feed URL to continue.")
        #expect(initialDestination.isPrimaryActionEnabled == false)

        state.updateAddFeedURLInput("not a url")

        guard case .addFeed(let invalidDestination)? = state.derivedViewState().presentedDestination else {
            Issue.record("Expected add-feed destination presentation after invalid URL input")
            return
        }

        #expect(invalidDestination.validationMessage == "Enter a valid site or feed URL.")
        #expect(invalidDestination.isPrimaryActionEnabled == false)

        state.updateAddFeedURLInput("example.com")

        guard case .addFeed(let siteDestination)? = state.derivedViewState().presentedDestination else {
            Issue.record("Expected add-feed destination presentation after site URL input")
            return
        }

        #expect(siteDestination.validationMessage == nil)
        #expect(siteDestination.normalizedURL == "https://example.com")
        #expect(siteDestination.isPrimaryActionEnabled)

        state.updateAddFeedURLInput(" https://example.com/feed.xml ")

        guard case .addFeed(let validDestination)? = state.derivedViewState().presentedDestination else {
            Issue.record("Expected add-feed destination presentation after URL input")
            return
        }

        #expect(validDestination.validationMessage == nil)
        #expect(validDestination.normalizedURL == "https://example.com/feed.xml")
        #expect(validDestination.isPrimaryActionEnabled)

        let preview = SourceManagementFeedPreview(
            requestedURL: "https://example.com/feed.xml",
            resolvedFeedURL: "https://example.com/feed.xml",
            title: "Example Feed",
            subtitle: "Preview subtitle",
            siteURL: "https://example.com/",
            iconURL: "https://example.com/icon.png",
            language: "en",
            kind: .rss,
            parserAnomalyCount: 0,
            rejectedEntryCount: 0,
            existingFeedID: nil
        )
        let requestURL = state.beginAddFeedPreviewLoading()
        state.applyLoadedAddFeedPreview(preview, requestURL: requestURL ?? "")

        guard case .addFeed(let previewDestination)? = state.derivedViewState().presentedDestination else {
            Issue.record("Expected add-feed destination presentation after preview loading")
            return
        }

        #expect(previewDestination.primaryActionTitle == "Confirm Feed")
        #expect(previewDestination.isPrimaryActionEnabled)
        #expect(previewDestination.preview?.title == "Example Feed")
        #expect(previewDestination.preview?.kindTitle == "RSS")
        #expect(previewDestination.placementOptions.map(\.title) == ["Ungrouped", "News", "Tech"])
        #expect(previewDestination.placementOptions.first?.isSelected == true)
        #expect(previewDestination.createFolderActionTitle == "Create New Folder")

        state.selectAddFeedFolderPlacement(.folder(techFolderID))

        state.confirmAddFeedPreview()

        guard case .addFeed(let confirmedDestination)? = state.derivedViewState().presentedDestination else {
            Issue.record("Expected add-feed destination presentation after confirmation")
            return
        }

        #expect(confirmedDestination.primaryActionTitle == "Add Feed")
        #expect(confirmedDestination.isPrimaryActionEnabled)
        #expect(confirmedDestination.status?.kind == .success)
        #expect(confirmedDestination.placementOptions.last?.isSelected == true)
        #expect(confirmedDestination.status?.detail?.contains("Tech") == true)

        let createCommand = state.beginAddFeedCreation()
        #expect(createCommand?.folderPlacement == .folder(techFolderID))
        state.applyCreatedAddFeed(
            SourceManagementFeedSummary(
                id: UUID(uuidString: "99999999-9999-9999-9999-999999999999")!,
                url: "https://example.com/feed.xml",
                title: "Example Feed",
                folderID: techFolderID,
                folderName: "Tech"
            )
        )

        guard case .addFeed(let createdDestination)? = state.derivedViewState().presentedDestination else {
            Issue.record("Expected add-feed destination presentation after feed creation")
            return
        }

        #expect(createdDestination.primaryActionTitle == "Feed Added")
        #expect(createdDestination.isPrimaryActionEnabled == false)
        #expect(createdDestination.status?.title == "Feed added")
    }

    @Test
    func sourceManagementScreenStateBuildsCreateFolderPresentationWithValidationAndPlacement() {
        var state = SourceManagementScreenState.makePreviewFixture()
        state.applyCreateFolderContext(
            folders: [
                SourceManagementFolderSummary(
                    id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                    name: "News",
                    sortOrder: 0,
                    feedCount: 5
                ),
                SourceManagementFolderSummary(
                    id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
                    name: "Tech",
                    sortOrder: 1,
                    feedCount: 3
                )
            ]
        )
        state.presentScenario(.createFolder)

        guard case .createFolder(let initialDestination)? = state.derivedViewState().presentedDestination else {
            Issue.record("Expected create-folder destination presentation")
            return
        }

        #expect(initialDestination.existingFolders.map(\.name) == ["News", "Tech"])
        #expect(initialDestination.placementDescription == "This folder will be added after 2 existing folders.")
        #expect(initialDestination.isPrimaryActionEnabled == false)

        state.updateCreateFolderNameInput("News")

        guard case .createFolder(let duplicateDestination)? = state.derivedViewState().presentedDestination else {
            Issue.record("Expected create-folder destination presentation after duplicate input")
            return
        }

        #expect(duplicateDestination.validationMessage == "A folder with this name already exists.")
        #expect(duplicateDestination.isPrimaryActionEnabled == false)

        state.updateCreateFolderNameInput("Research")

        guard case .createFolder(let validDestination)? = state.derivedViewState().presentedDestination else {
            Issue.record("Expected create-folder destination presentation after valid input")
            return
        }

        #expect(validDestination.validationMessage == nil)
        #expect(validDestination.isPrimaryActionEnabled)
    }

    @Test
    func sourceManagementScreenStateBuildsMoveSourcePresentationWithFeedAndPlacementSelection() {
        var state = SourceManagementScreenState.makePreviewFixture()
        let newsFolderID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        let techFolderID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
        state.applyMoveSourceContext(
            feeds: [
                SourceManagementFeedSummary(
                    id: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!,
                    url: "https://example.com/apple.xml",
                    title: "Apple Feed",
                    folderID: newsFolderID,
                    folderName: "News"
                ),
                SourceManagementFeedSummary(
                    id: UUID(uuidString: "88888888-8888-8888-8888-888888888888")!,
                    url: "https://example.com/beta.xml",
                    title: "Beta Feed",
                    folderID: nil,
                    folderName: nil
                )
            ],
            folders: [
                SourceManagementFolderSummary(
                    id: newsFolderID,
                    name: "News",
                    sortOrder: 0,
                    feedCount: 2
                ),
                SourceManagementFolderSummary(
                    id: techFolderID,
                    name: "Tech",
                    sortOrder: 1,
                    feedCount: 6
                )
            ]
        )
        state.presentScenario(.moveSource)

        guard case .moveSource(let initialDestination)? = state.derivedViewState().presentedDestination else {
            Issue.record("Expected move-source destination presentation")
            return
        }

        #expect(initialDestination.feeds.map(\.title) == ["Apple Feed", "Beta Feed"])
        #expect(initialDestination.feeds.first?.isSelected == true)
        #expect(initialDestination.placementOptions.map(\.title) == ["Ungrouped", "News", "Tech"])
        #expect(initialDestination.isPrimaryActionEnabled == false)

        state.selectMoveSourcePlacement(.folder(techFolderID))

        guard case .moveSource(let changedDestination)? = state.derivedViewState().presentedDestination else {
            Issue.record("Expected move-source destination presentation after placement change")
            return
        }

        #expect(changedDestination.isPrimaryActionEnabled)
        #expect(changedDestination.placementOptions.last?.isSelected == true)
    }
}
