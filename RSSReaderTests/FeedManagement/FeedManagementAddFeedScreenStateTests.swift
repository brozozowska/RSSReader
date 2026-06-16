import Foundation
import Testing
@testable import RSSReader

@Suite("Feed Management / Screen State / Add Feed")
@MainActor
struct FeedManagementAddFeedScreenStateTests {
    @Test
    func feedManagementScreenStateBuildsAddFeedPresentationWithPreviewAndSingleSaveState() {
        var state = FeedManagementScreenState.makePreviewFixture()
        let newsFolderID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let techFolderID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        state.applyAddFeedFolderContext(
            folders: [
                FeedManagementFolderSummary(
                    id: newsFolderID,
                    name: "News",
                    sortOrder: 0,
                    feedCount: 5
                ),
                FeedManagementFolderSummary(
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

        #expect(initialDestination.validationMessage == FeedManagementLocalization.enterFeedURLValidation)
        #expect(initialDestination.isPrimaryActionEnabled == false)

        state.updateAddFeedURLInput("not a url")

        guard case .addFeed(let invalidDestination)? = state.derivedViewState().presentedDestination else {
            Issue.record("Expected add-feed destination presentation after invalid URL input")
            return
        }

        #expect(invalidDestination.validationMessage == FeedManagementLocalization.invalidFeedURLValidation)
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

        let preview = FeedManagementFeedPreview(
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
        let previewCommand = state.beginAddFeedPreviewLoading()
        if let previewCommand {
            state.applyLoadedAddFeedPreview(preview, command: previewCommand)
        }

        guard case .addFeed(let previewDestination)? = state.derivedViewState().presentedDestination else {
            Issue.record("Expected add-feed destination presentation after preview loading")
            return
        }

        #expect(previewDestination.primaryActionTitle == FeedManagementLocalization.addFeedTitle)
        #expect(previewDestination.isPrimaryActionEnabled)
        #expect(previewDestination.isConfirmationActionEnabled)
        #expect(previewDestination.preview?.title == "Example Feed")
        #expect(previewDestination.preview?.kindTitle == FeedManagementLocalization.rssFeedKindTitle)
        #expect(previewDestination.placementOptions.map(\.title) == [FeedManagementLocalization.ungroupedTitle, "News", "Tech"])
        #expect(previewDestination.placementOptions.first?.isSelected == true)
        #expect(previewDestination.createFolderActionTitle == FeedManagementLocalization.createNewFolderAction)

        state.selectAddFeedFolderPlacement(.folder(techFolderID))

        let createCommand = state.beginAddFeedCreation()
        #expect(createCommand?.folderPlacement == .folder(techFolderID))
        state.applyCreatedAddFeed(
            FeedManagementFeedSummary(
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

        #expect(createdDestination.primaryActionTitle == FeedManagementLocalization.feedAddedAction)
        #expect(createdDestination.isPrimaryActionEnabled == false)
        #expect(createdDestination.status?.title == FeedManagementLocalization.feedAddedTitle)
    }

    @Test
    func feedManagementScreenStateHidesFolderPlacementWhenEditingFeed() {
        var state = FeedManagementScreenState.makePreviewFixture()
        let newsFolderID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let techFolderID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        state.applyAddFeedEditContext(
            feed: FeedManagementFeedSummary(
                id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
                url: "https://example.com/original.xml",
                title: "Original Feed",
                folderID: newsFolderID,
                folderName: "News"
            ),
            folders: [
                FeedManagementFolderSummary(
                    id: newsFolderID,
                    name: "News",
                    sortOrder: 0,
                    feedCount: 1
                ),
                FeedManagementFolderSummary(
                    id: techFolderID,
                    name: "Tech",
                    sortOrder: 1,
                    feedCount: 0
                )
            ]
        )
        state.presentScenario(.addFeed)

        guard case .addFeed(let editDestination)? = state.derivedViewState().presentedDestination else {
            Issue.record("Expected add-feed destination presentation for feed editing")
            return
        }

        #expect(editDestination.title == FeedManagementLocalization.editFeedTitle)
        #expect(editDestination.placementOptions.isEmpty)
        #expect(editDestination.createFolderActionTitle == nil)

        state.updateAddFeedURLInput("https://example.com/updated.xml")
        guard let previewCommand = state.beginAddFeedPreviewLoading() else {
            Issue.record("Expected preview command for edited feed URL")
            return
        }
        state.applyLoadedAddFeedPreview(
            FeedManagementFeedPreview(
                requestedURL: previewCommand.urlString,
                resolvedFeedURL: previewCommand.urlString,
                title: "Updated Feed",
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

        let updateCommand = state.beginAddFeedUpdate()
        #expect(updateCommand?.folderPlacement == .folder(newsFolderID))
    }

    @Test
    func feedManagementScreenStateRequiresPreviewBeforeSavingChangedEditFeedURL() {
        var state = FeedManagementScreenState.makePreviewFixture()
        state.applyAddFeedEditContext(
            feed: FeedManagementFeedSummary(
                id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
                url: "https://example.com/original.xml",
                title: "Original Feed",
                folderID: nil,
                folderName: nil
            ),
            folders: []
        )
        state.presentScenario(.addFeed)

        state.updateAddFeedDisplayNameInput("Renamed Feed")
        let displayNameOnlyCommand = state.beginAddFeedUpdate()
        #expect(displayNameOnlyCommand?.preview == nil)

        state.updateAddFeedURLInput("https://example.com/changed.xml")

        #expect(state.shouldPreviewAddFeedBeforeSaving())
        #expect(state.beginAddFeedUpdate() == nil)

        guard let previewCommand = state.beginAddFeedPreviewLoading() else {
            Issue.record("Expected preview command for changed edit URL")
            return
        }

        #expect(previewCommand.urlString == "https://example.com/changed.xml")
    }

    @Test
    func feedManagementScreenStateIgnoresStaleAddFeedPreviewCompletion() {
        var state = FeedManagementScreenState.makePreviewFixture()
        state.presentScenario(.addFeed)
        state.updateAddFeedURLInput("example.com/feed.xml")

        guard let activeCommand = state.beginAddFeedPreviewLoading() else {
            Issue.record("Expected first preview command")
            return
        }

        let secondCommand = state.beginAddFeedPreviewLoading()
        #expect(secondCommand == nil)

        let staleCommand = FeedManagementAddFeedPreviewCommand(
            requestID: UUID(),
            urlString: activeCommand.urlString
        )
        state.applyAddFeedPreviewFailure(
            FeedManagementAddFeedStatusPresentation(
                title: "Preview could not be loaded",
                kind: .failure,
                detail: "Unable to check this feed right now."
            ),
            command: staleCommand
        )

        guard case .addFeed(let loadingDestination)? = state.derivedViewState().presentedDestination else {
            Issue.record("Expected add-feed destination after stale completion")
            return
        }

        #expect(loadingDestination.isLoadingPreview)
        #expect(loadingDestination.status == nil)
        #expect(loadingDestination.preview == nil)
    }

    @Test
    func feedManagementScreenStateKeepsAddFeedPreviewLoadingForRepeatedURLBindingSet() {
        var state = FeedManagementScreenState.makePreviewFixture()
        state.presentScenario(.addFeed)
        state.updateAddFeedURLInput("example.com/feed.xml")

        guard let activeCommand = state.beginAddFeedPreviewLoading() else {
            Issue.record("Expected preview command")
            return
        }

        state.updateAddFeedURLInput("example.com/feed.xml")

        guard case .addFeed(let loadingDestination)? = state.derivedViewState().presentedDestination else {
            Issue.record("Expected add-feed destination after repeated URL binding set")
            return
        }

        #expect(loadingDestination.isLoadingPreview)
        #expect(loadingDestination.preview == nil)
        #expect(loadingDestination.status == nil)

        let preview = FeedManagementFeedPreview(
            requestedURL: activeCommand.urlString,
            resolvedFeedURL: activeCommand.urlString,
            title: "Example Feed",
            subtitle: nil,
            siteURL: "https://example.com/",
            iconURL: nil,
            language: "en",
            kind: .rss,
            parserAnomalyCount: 0,
            rejectedEntryCount: 0,
            existingFeedID: nil
        )
        state.applyLoadedAddFeedPreview(preview, command: activeCommand)

        guard case .addFeed(let loadedDestination)? = state.derivedViewState().presentedDestination else {
            Issue.record("Expected add-feed destination after preview completion")
            return
        }

        #expect(loadedDestination.preview?.title == "Example Feed")
        #expect(loadedDestination.isConfirmationActionEnabled)
    }

    @Test
    func feedManagementScreenStateStartsNewAddFeedPreviewLoadingAfterFailureAndURLChange() {
        var state = FeedManagementScreenState.makePreviewFixture()
        state.presentScenario(.addFeed)
        state.updateAddFeedURLInput("thecode.")

        guard let failedCommand = state.beginAddFeedPreviewLoading() else {
            Issue.record("Expected failed preview command")
            return
        }

        state.applyAddFeedPreviewFailure(
            FeedManagementAddFeedStatusPresentation(
                title: "Feed was not found",
                kind: .failure,
                detail: "The app could not find a supported RSS or Atom feed for this address."
            ),
            command: failedCommand
        )

        guard case .addFeed(let failureDestination)? = state.derivedViewState().presentedDestination else {
            Issue.record("Expected add-feed destination after preview failure")
            return
        }

        #expect(failureDestination.status?.kind == .failure)
        #expect(failureDestination.isLoadingPreview == false)

        state.updateAddFeedURLInput("thecode.media")

        guard case .addFeed(let retryReadyDestination)? = state.derivedViewState().presentedDestination else {
            Issue.record("Expected add-feed destination after URL change")
            return
        }

        #expect(retryReadyDestination.status == nil)
        #expect(retryReadyDestination.isPrimaryActionEnabled)

        guard state.beginAddFeedPreviewLoading() != nil else {
            Issue.record("Expected retry preview command")
            return
        }

        guard case .addFeed(let retryLoadingDestination)? = state.derivedViewState().presentedDestination else {
            Issue.record("Expected add-feed destination during retry preview loading")
            return
        }

        #expect(retryLoadingDestination.isLoadingPreview)
        #expect(retryLoadingDestination.preview == nil)
        #expect(retryLoadingDestination.status == nil)
    }
}
