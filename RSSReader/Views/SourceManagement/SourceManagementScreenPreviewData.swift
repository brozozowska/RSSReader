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

#Preview("Source Management Screen · Add Feed Preview") {
    SourceManagementScreenPreviewContainer(
        screenState: .previewAddFeed(
            urlInput: "https://example.com/feed.xml",
            preview: SourceManagementFeedPreview(
                requestedURL: "https://example.com/feed.xml",
                resolvedFeedURL: "https://example.com/feed.xml",
                title: "Example Feed",
                subtitle: "Preview from sample metadata",
                siteURL: "https://example.com/",
                iconURL: "https://example.com/icon.png",
                language: "en",
                kind: .rss,
                parserAnomalyCount: 0,
                rejectedEntryCount: 0,
                existingFeedID: nil
            )
        )
    )
}

#Preview("Source Management Screen · Add Feed Confirmed") {
    SourceManagementScreenPreviewContainer(
        screenState: .previewAddFeed(
            urlInput: "https://example.com/feed.xml",
            preview: SourceManagementFeedPreview(
                requestedURL: "https://example.com/feed.xml",
                resolvedFeedURL: "https://example.com/feed.xml",
                title: "Example Feed",
                subtitle: "Preview from sample metadata",
                siteURL: "https://example.com/",
                iconURL: "https://example.com/icon.png",
                language: "en",
                kind: .rss,
                parserAnomalyCount: 1,
                rejectedEntryCount: 2,
                existingFeedID: nil
            ),
            isConfirmed: true
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
