import SwiftUI

#Preview("Source Management · Entry") {
    SourceManagementScreenPreviewContainer(
        screenState: SourceManagementScreenPreviewFactory.makeEntryState()
    )
}

#Preview("Source Management · Add Feed Draft") {
    SourceManagementScreenPreviewContainer(
        screenState: SourceManagementScreenPreviewFactory.makeAddFeedDraftState()
    )
}

#Preview("Source Management · Add Feed Preview") {
    SourceManagementScreenPreviewContainer(
        screenState: SourceManagementScreenPreviewFactory.makeAddFeedPreviewState()
    )
}

#Preview("Source Management · Add Feed Duplicate") {
    SourceManagementScreenPreviewContainer(
        screenState: SourceManagementScreenPreviewFactory.makeAddFeedDuplicateState()
    )
}

#Preview("Source Management · Add Feed Saved") {
    SourceManagementScreenPreviewContainer(
        screenState: SourceManagementScreenPreviewFactory.makeAddFeedSavedState()
    )
}

#Preview("Source Management · Edit Feed") {
    SourceManagementScreenPreviewContainer(
        screenState: SourceManagementScreenPreviewFactory.makeEditFeedState()
    )
}

#Preview("Source Management · Create Folder First") {
    SourceManagementScreenPreviewContainer(
        screenState: SourceManagementScreenPreviewFactory.makeCreateFirstFolderState()
    )
}

#Preview("Source Management · Create Folder Saved") {
    SourceManagementScreenPreviewContainer(
        screenState: SourceManagementScreenPreviewFactory.makeCreateFolderSavedState()
    )
}

#Preview("Source Management · Edit Folder") {
    SourceManagementScreenPreviewContainer(
        screenState: SourceManagementScreenPreviewFactory.makeEditFolderState()
    )
}

#Preview("Source Management · Move Source") {
    SourceManagementScreenPreviewContainer(
        screenState: SourceManagementScreenPreviewFactory.makeMoveSourceState()
    )
}

#Preview("Source Management · Move Source Saved") {
    SourceManagementScreenPreviewContainer(
        screenState: SourceManagementScreenPreviewFactory.makeMoveSourceSavedState()
    )
}

private struct SourceManagementScreenPreviewContainer: View {
    let dependencies: AppDependencies
    let screenState: SourceManagementScreenState

    init(screenState: SourceManagementScreenState) {
        self.dependencies = SourceManagementScreenPreviewFactory.makeDependencies()
        self.screenState = screenState
    }

    var body: some View {
        SourceManagementScreenView(
            dismiss: {},
            previewScreenState: screenState
        )
        .environment(\.appDependencies, dependencies)
        .environment(AppState())
    }
}

private enum SourceManagementScreenPreviewFactory {
    enum SampleIDs {
        static let newsFolderID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        static let researchFolderID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        static let macstoriesFeedID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        static let sixcolorsFeedID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        static let createdFeedID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        static let firstFolderID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
    }

    static let folders: [SourceManagementFolderSummary] = [
        SourceManagementFolderSummary(
            id: SampleIDs.newsFolderID,
            name: "News",
            sortOrder: 0,
            feedCount: 4
        ),
        SourceManagementFolderSummary(
            id: SampleIDs.researchFolderID,
            name: "Research",
            sortOrder: 1,
            feedCount: 2
        )
    ]

    static let feeds: [SourceManagementFeedSummary] = [
        SourceManagementFeedSummary(
            id: SampleIDs.macstoriesFeedID,
            url: "https://www.macstories.net/feed/",
            title: "MacStories",
            folderID: SampleIDs.newsFolderID,
            folderName: "News"
        ),
        SourceManagementFeedSummary(
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

    static func makeEntryState() -> SourceManagementScreenState {
        makeBaseState()
    }

    static func makeAddFeedDraftState() -> SourceManagementScreenState {
        makeAddFeedState(
            urlInput: " https://feedbin.com/blog.xml ",
            folders: folders
        )
    }

    static func makeAddFeedPreviewState() -> SourceManagementScreenState {
        makeAddFeedState(
            urlInput: samplePreview().requestedURL,
            preview: samplePreview(),
            folders: folders,
            selectedPlacement: .folder(SampleIDs.researchFolderID)
        )
    }

    static func makeAddFeedDuplicateState() -> SourceManagementScreenState {
        makeAddFeedState(
            urlInput: samplePreview(existingFeedID: SampleIDs.macstoriesFeedID).requestedURL,
            preview: samplePreview(existingFeedID: SampleIDs.macstoriesFeedID),
            folders: folders
        )
    }

    static func makeAddFeedSavedState() -> SourceManagementScreenState {
        var state = makeAddFeedState(
            urlInput: samplePreview().requestedURL,
            preview: samplePreview(),
            folders: folders,
            selectedPlacement: .folder(SampleIDs.researchFolderID)
        )
        _ = state.beginAddFeedCreation()
        state.applyCreatedAddFeed(
            SourceManagementFeedSummary(
                id: SampleIDs.createdFeedID,
                url: samplePreview().resolvedFeedURL,
                title: samplePreview().title,
                folderID: SampleIDs.researchFolderID,
                folderName: "Research"
            )
        )
        return state
    }

    static func makeEditFeedState() -> SourceManagementScreenState {
        var state = makeBaseState()
        state.applyAddFeedEditContext(feed: feeds[0], folders: folders)
        state.presentScenario(.addFeed)
        return state
    }

    static func makeCreateFirstFolderState() -> SourceManagementScreenState {
        var state = makeBaseState()
        state.applyCreateFolderContext(folders: [])
        state.updateCreateFolderNameInput("Reading List")
        state.presentScenario(.createFolder)
        return state
    }

    static func makeCreateFolderSavedState() -> SourceManagementScreenState {
        var state = makeBaseState()
        state.applyCreateFolderContext(folders: [])
        state.updateCreateFolderNameInput("Reading List")
        state.beginCreateFolderSubmission()
        state.applyCreatedFolder(
            SourceManagementFolderSummary(
                id: SampleIDs.firstFolderID,
                name: "Reading List",
                sortOrder: 0,
                feedCount: 0
            )
        )
        state.presentScenario(.createFolder)
        return state
    }

    static func makeEditFolderState() -> SourceManagementScreenState {
        var state = makeBaseState()
        state.applyCreateFolderEditContext(folder: folders[0], folders: folders)
        state.presentScenario(.createFolder)
        return state
    }

    static func makeMoveSourceState() -> SourceManagementScreenState {
        var state = makeMoveSourceBaseState(feeds: feeds, folders: folders)
        state.selectMoveSourceFeed(SampleIDs.sixcolorsFeedID)
        state.selectMoveSourcePlacement(.folder(SampleIDs.researchFolderID))
        return state
    }

    static func makeMoveSourceSavedState() -> SourceManagementScreenState {
        var state = makeMoveSourceState()
        state.beginMoveSourceSubmission()
        state.applyMovedSource(
            SourceManagementFeedSummary(
                id: SampleIDs.sixcolorsFeedID,
                url: "https://sixcolors.com/feed/",
                title: "Six Colors",
                folderID: SampleIDs.researchFolderID,
                folderName: "Research"
            )
        )
        return state
    }

    static func samplePreview(existingFeedID: UUID? = nil) -> SourceManagementFeedPreview {
        SourceManagementFeedPreview(
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
        presentedScenarioID: SourceManagementScenarioID? = nil
    ) -> SourceManagementScreenState {
        var state = SourceManagementScreenState()
        if let presentedScenarioID {
            state.presentScenario(presentedScenarioID)
        }
        return state
    }

    static func makeAddFeedState(
        urlInput: String = "",
        preview: SourceManagementFeedPreview? = nil,
        failureMessage: String? = nil,
        folders: [SourceManagementFolderSummary] = [],
        selectedPlacement: SourceManagementFolderPlacement = .ungrouped
    ) -> SourceManagementScreenState {
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
                SourceManagementAddFeedStatusPresentation(
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

    static func makeMoveSourceBaseState(
        feeds: [SourceManagementFeedSummary] = [],
        folders: [SourceManagementFolderSummary] = []
    ) -> SourceManagementScreenState {
        var state = makeBaseState()
        state.applyMoveSourceContext(feeds: feeds, folders: folders)
        state.presentScenario(.moveSource)
        return state
    }
}
