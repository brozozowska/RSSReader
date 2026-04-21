import SwiftUI

#Preview("Source Management Screen") {
    SourceManagementScreenPreviewContainer(
        screenState: .previewLoaded()
    )
}

#Preview("Source Management Screen · Move Sources") {
    SourceManagementScreenPreviewContainer(
        screenState: .previewMoveSource(
            feeds: [
                SourceManagementFeedSummary(
                    id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                    url: "https://example.com/feed.xml",
                    title: "Example Feed",
                    folderID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                    folderName: "News"
                ),
                SourceManagementFeedSummary(
                    id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
                    url: "https://example.com/ungrouped.xml",
                    title: "Ungrouped Feed",
                    folderID: nil,
                    folderName: nil
                )
            ],
            folders: [
                SourceManagementFolderSummary(
                    id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                    name: "News",
                    sortOrder: 0,
                    feedCount: 4
                ),
                SourceManagementFolderSummary(
                    id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                    name: "Tech",
                    sortOrder: 1,
                    feedCount: 7
                )
            ]
        )
    )
}

#Preview("Source Management Screen · Add Feed") {
    SourceManagementScreenPreviewContainer(
        screenState: .previewAddFeed(
            urlInput: " https://example.com/feed.xml ",
            folders: [
                SourceManagementFolderSummary(
                    id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                    name: "News",
                    sortOrder: 0,
                    feedCount: 4
                )
            ]
        )
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
            ),
            folders: [
                SourceManagementFolderSummary(
                    id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                    name: "News",
                    sortOrder: 0,
                    feedCount: 4
                ),
                SourceManagementFolderSummary(
                    id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                    name: "Tech",
                    sortOrder: 1,
                    feedCount: 7
                )
            ]
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
            isConfirmed: true,
            folders: [
                SourceManagementFolderSummary(
                    id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                    name: "News",
                    sortOrder: 0,
                    feedCount: 4
                ),
                SourceManagementFolderSummary(
                    id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                    name: "Tech",
                    sortOrder: 1,
                    feedCount: 7
                )
            ],
            selectedPlacement: .folder(
                UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
            )
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
        .environment(AppState())
    }
}

private enum SourceManagementScreenPreviewFactory {
    @MainActor
    static func makeDependencies() -> AppDependencies {
        AppDependencies.makeDefault()
    }
}
