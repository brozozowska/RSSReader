import SwiftUI

#Preview("Feed Management · Entry") {
    FeedManagementScreenPreviewContainer(
        screenState: FeedManagementScreenPreviewFactory.makeEntryState()
    )
}

#Preview("Feed Management · Add Feed Draft") {
    FeedManagementScreenPreviewContainer(
        screenState: FeedManagementScreenPreviewFactory.makeAddFeedDraftState()
    )
}

#Preview("Feed Management · Add Feed Preview") {
    FeedManagementScreenPreviewContainer(
        screenState: FeedManagementScreenPreviewFactory.makeAddFeedPreviewState()
    )
}

#Preview("Feed Management · Add Feed Duplicate") {
    FeedManagementScreenPreviewContainer(
        screenState: FeedManagementScreenPreviewFactory.makeAddFeedDuplicateState()
    )
}

#Preview("Feed Management · Add Feed Saved") {
    FeedManagementScreenPreviewContainer(
        screenState: FeedManagementScreenPreviewFactory.makeAddFeedSavedState()
    )
}

#Preview("Feed Management · Rename Feed") {
    FeedManagementScreenPreviewContainer(
        screenState: FeedManagementScreenPreviewFactory.makeEditFeedState()
    )
}

#Preview("Feed Management · Create Folder First") {
    FeedManagementScreenPreviewContainer(
        screenState: FeedManagementScreenPreviewFactory.makeCreateFirstFolderState()
    )
}

#Preview("Feed Management · Create Folder Saved") {
    FeedManagementScreenPreviewContainer(
        screenState: FeedManagementScreenPreviewFactory.makeCreateFolderSavedState()
    )
}

#Preview("Feed Management · Rename Folder") {
    FeedManagementScreenPreviewContainer(
        screenState: FeedManagementScreenPreviewFactory.makeEditFolderState()
    )
}

#Preview("Feed Management · Move Feed") {
    FeedManagementScreenPreviewContainer(
        screenState: FeedManagementScreenPreviewFactory.makeMoveFeedState()
    )
}

#Preview("Feed Management · Move Feed Saved") {
    FeedManagementScreenPreviewContainer(
        screenState: FeedManagementScreenPreviewFactory.makeMoveFeedSavedState()
    )
}

private struct FeedManagementScreenPreviewContainer: View {
    let dependencies: AppDependencies
    let screenState: FeedManagementScreenState

    init(screenState: FeedManagementScreenState) {
        self.dependencies = FeedManagementScreenPreviewFactory.makeDependencies()
        self.screenState = screenState
    }

    var body: some View {
        FeedManagementScreenView(
            dismiss: {},
            previewScreenState: screenState
        )
        .environment(\.appDependencies, dependencies)
        .environment(AppState())
    }
}

private enum FeedManagementScreenPreviewFactory {
    enum SampleIDs {
        static let newsFolderID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        static let researchFolderID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        static let macstoriesFeedID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        static let sixcolorsFeedID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        static let createdFeedID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        static let firstFolderID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
    }

    static let folders: [FeedManagementFolderSummary] = [
        FeedManagementFolderSummary(
            id: SampleIDs.newsFolderID,
            name: "News",
            sortOrder: 0,
            feedCount: 4
        ),
        FeedManagementFolderSummary(
            id: SampleIDs.researchFolderID,
            name: "Research",
            sortOrder: 1,
            feedCount: 2
        )
    ]

    static let feeds: [FeedManagementFeedSummary] = [
        FeedManagementFeedSummary(
            id: SampleIDs.macstoriesFeedID,
            url: "https://www.macstories.net/feed/",
            title: "MacStories",
            folderID: SampleIDs.newsFolderID,
            folderName: "News"
        ),
        FeedManagementFeedSummary(
            id: SampleIDs.sixcolorsFeedID,
            url: "https://sixcolors.com/feed/",
            title: "Six Colors",
            folderID: nil,
            folderName: nil
        )
    ]

    @MainActor
    static func makeDependencies() -> AppDependencies {
        AppDependencies.makeDefault()
    }

    static func makeEntryState() -> FeedManagementScreenState {
        makeBaseState()
    }

    static func makeAddFeedDraftState() -> FeedManagementScreenState {
        makeAddFeedState(
            urlInput: " https://feedbin.com/blog.xml ",
            folders: folders
        )
    }

    static func makeAddFeedPreviewState() -> FeedManagementScreenState {
        makeAddFeedState(
            urlInput: samplePreview().requestedURL,
            preview: samplePreview(),
            folders: folders,
            selectedPlacement: .folder(SampleIDs.researchFolderID)
        )
    }

    static func makeAddFeedDuplicateState() -> FeedManagementScreenState {
        makeAddFeedState(
            urlInput: samplePreview(existingFeedID: SampleIDs.macstoriesFeedID).requestedURL,
            preview: samplePreview(existingFeedID: SampleIDs.macstoriesFeedID),
            folders: folders
        )
    }

    static func makeAddFeedSavedState() -> FeedManagementScreenState {
        var state = makeAddFeedState(
            urlInput: samplePreview().requestedURL,
            preview: samplePreview(),
            folders: folders,
            selectedPlacement: .folder(SampleIDs.researchFolderID)
        )
        _ = state.beginAddFeedCreation()
        state.applyCreatedAddFeed(
            FeedManagementFeedSummary(
                id: SampleIDs.createdFeedID,
                url: samplePreview().resolvedFeedURL,
                title: samplePreview().title,
                folderID: SampleIDs.researchFolderID,
                folderName: "Research"
            )
        )
        return state
    }

    static func makeEditFeedState() -> FeedManagementScreenState {
        var state = makeBaseState()
        state.applyAddFeedEditContext(feed: feeds[0], folders: folders)
        state.presentScenario(.addFeed)
        return state
    }

    static func makeCreateFirstFolderState() -> FeedManagementScreenState {
        var state = makeBaseState()
        state.applyCreateFolderContext(folders: [])
        state.updateCreateFolderNameInput("Reading List")
        state.presentScenario(.createFolder)
        return state
    }

    static func makeCreateFolderSavedState() -> FeedManagementScreenState {
        var state = makeBaseState()
        state.applyCreateFolderContext(folders: [])
        state.updateCreateFolderNameInput("Reading List")
        state.beginCreateFolderSubmission()
        state.applyCreatedFolder(
            FeedManagementFolderSummary(
                id: SampleIDs.firstFolderID,
                name: "Reading List",
                sortOrder: 0,
                feedCount: 0
            )
        )
        state.presentScenario(.createFolder)
        return state
    }

    static func makeEditFolderState() -> FeedManagementScreenState {
        var state = makeBaseState()
        state.applyCreateFolderEditContext(folder: folders[0], folders: folders)
        state.presentScenario(.createFolder)
        return state
    }

    static func makeMoveFeedState() -> FeedManagementScreenState {
        var state = makeMoveFeedBaseState(feeds: feeds, folders: folders)
        state.selectMoveFeedFeed(SampleIDs.sixcolorsFeedID)
        state.selectMoveFeedPlacement(.folder(SampleIDs.researchFolderID))
        return state
    }

    static func makeMoveFeedSavedState() -> FeedManagementScreenState {
        var state = makeMoveFeedState()
        state.beginMoveFeedSubmission()
        state.applyMovedFeed(
            FeedManagementFeedSummary(
                id: SampleIDs.sixcolorsFeedID,
                url: "https://sixcolors.com/feed/",
                title: "Six Colors",
                folderID: SampleIDs.researchFolderID,
                folderName: "Research"
            )
        )
        return state
    }

    static func samplePreview(existingFeedID: UUID? = nil) -> FeedManagementFeedPreview {
        FeedManagementFeedPreview(
            requestedURL: "https://feedbin.com/blog.xml",
            resolvedFeedURL: "https://feedbin.com/blog.xml",
            title: "Feedbin Blog",
            subtitle: "Product notes and workflow updates from Feedbin.",
            siteURL: "https://feedbin.com/",
            iconURL: "https://feedbin.com/icon.png",
            language: "en",
            kind: .rss,
            parserAnomalyCount: 1,
            rejectedEntryCount: 0,
            existingFeedID: existingFeedID
        )
    }

    static func makeBaseState(
        presentedScenarioID: FeedManagementScenarioID? = nil
    ) -> FeedManagementScreenState {
        var state = FeedManagementScreenState()
        if let presentedScenarioID {
            state.presentScenario(presentedScenarioID)
        }
        return state
    }

    static func makeAddFeedState(
        urlInput: String = "",
        preview: FeedManagementFeedPreview? = nil,
        failureMessage: String? = nil,
        folders: [FeedManagementFolderSummary] = [],
        selectedPlacement: FeedManagementFolderPlacement = .ungrouped
    ) -> FeedManagementScreenState {
        var state = makeBaseState()
        state.updateAddFeedURLInput(urlInput)
        state.applyAddFeedFolderContext(folders: folders)
        state.selectAddFeedFolderPlacement(selectedPlacement)
        if let preview {
            if let previewCommand = state.beginAddFeedPreviewLoading() {
                state.applyLoadedAddFeedPreview(preview, command: previewCommand)
            }
        } else if let failureMessage {
            let previewCommand = state.beginAddFeedPreviewLoading()
            state.applyAddFeedPreviewFailure(
                FeedManagementAddFeedStatusPresentation(
                    title: "Preview could not be loaded",
                    kind: .failure,
                    detail: failureMessage
                ),
                command: previewCommand
            )
        }
        state.presentScenario(.addFeed)
        return state
    }

    static func makeMoveFeedBaseState(
        feeds: [FeedManagementFeedSummary] = [],
        folders: [FeedManagementFolderSummary] = []
    ) -> FeedManagementScreenState {
        var state = makeBaseState()
        state.applyMoveFeedContext(feeds: feeds, folders: folders)
        state.presentScenario(.moveFeed)
        return state
    }
}
