import Foundation

@MainActor
struct FeedManagementSummaryMapper {
    let feedRepository: any FeedRepository

    func folderSummary(from folder: Folder) throws -> FeedManagementFolderSummary {
        FeedManagementFolderSummary(
            id: folder.id,
            name: folder.name,
            sortOrder: folder.sortOrder,
            feedCount: try feedRepository.countFeeds(inFolderID: folder.id)
        )
    }

    func feedSummary(from feed: Feed) -> FeedManagementFeedSummary {
        FeedManagementFeedSummary(
            id: feed.id,
            url: feed.url,
            title: feed.displayTitle,
            metadataTitle: feed.title,
            displayTitleOverride: feed.displayTitleOverride,
            folderID: feed.folder?.id,
            folderName: feed.folder?.name
        )
    }
}
