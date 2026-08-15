import Foundation

@MainActor
protocol SidebarQueryService {
    func fetchSnapshot() throws -> SidebarSnapshotDTO
}

@MainActor
final class DefaultSidebarQueryService: SidebarQueryService {
    private let feedRepository: any FeedRepository
    private let folderRepository: any FolderRepository
    private let articleStateRepository: any ArticleStateRepository

    init(
        feedRepository: any FeedRepository,
        folderRepository: any FolderRepository,
        articleStateRepository: any ArticleStateRepository
    ) {
        self.feedRepository = feedRepository
        self.folderRepository = folderRepository
        self.articleStateRepository = articleStateRepository
    }

    func fetchSnapshot() throws -> SidebarSnapshotDTO {
        let baseFeeds = try feedRepository.fetchSidebarItems()
        let folders = try folderRepository.fetchAllFolders().map(FolderSidebarItem.init(folder:))
        let aggregateCounts = try articleStateRepository.fetchAggregateCounts(
            feedIDs: baseFeeds.map(\.id)
        )
        let feeds = baseFeeds.map { feed in
            feed.withCounts(
                unreadCount: aggregateCounts.unreadByFeedID[feed.id, default: 0],
                starredCount: aggregateCounts.starredByFeedID[feed.id, default: 0]
            )
        }

        return SidebarSnapshotDTO(
            folders: folders,
            feeds: feeds,
            unreadSmartCount: feeds.reduce(0) { $0 + $1.unreadCount },
            starredSmartCount: feeds.reduce(0) { $0 + $1.starredCount },
            starredFeedIDs: Set(feeds.filter { $0.starredCount > 0 }.map(\.id))
        )
    }
}
