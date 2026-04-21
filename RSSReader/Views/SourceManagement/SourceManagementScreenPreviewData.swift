import SwiftUI

#Preview("Source Management Screen") {
    SourceManagementScreenPreviewContainer(
        screenState: .previewLoaded()
    )
}

#Preview("Source Management Screen · Move Sources") {
    SourceManagementScreenPreviewContainer(
        screenState: .previewLoaded(presentedScenarioID: .moveSource)
    )
}

#Preview("Source Management Screen · Add Feed") {
    SourceManagementScreenPreviewContainer(
        screenState: .previewAddFeed(urlInput: " https://example.com/feed.xml ")
    )
}

#Preview("Source Management Screen · Add Feed Ready") {
    SourceManagementScreenPreviewContainer(
        screenState: .previewAddFeed(
            urlInput: "https://example.com/feed.xml",
            preparedPreviewURL: "https://example.com/feed.xml"
        )
    )
}

#Preview("Source Management Screen · Create Folder") {
    SourceManagementScreenPreviewContainer(
        screenState: .previewCreateFolder(nameInput: "Research")
    )
}

#Preview("Source Management Screen · Create Folder Success") {
    SourceManagementScreenPreviewContainer(
        screenState: .previewCreateFolder(
            feedback: SourceManagementCreateFolderFeedbackPresentation(
                kind: .success,
                title: "Folder created",
                detail: "\"Research\" will appear as sidebar folder #3."
            )
        )
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
    }
}

private enum SourceManagementScreenPreviewFactory {
    @MainActor
    static func makeDependencies() -> AppDependencies {
        AppDependencies.makeDefault()
    }
}
