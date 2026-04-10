import Foundation

@MainActor
protocol SourcesSidebarQueryService {
    func fetchSnapshot() throws -> SourcesSidebarSnapshotDTO
}

@MainActor
final class DefaultSourcesSidebarQueryService: SourcesSidebarQueryService {
    private let feedRepository: any FeedRepository
    private let articleStateRepository: any ArticleStateRepository
    private let articleQueryService: any ArticleQueryService

    init(
        feedRepository: any FeedRepository,
        articleStateRepository: any ArticleStateRepository,
        articleQueryService: any ArticleQueryService
    ) {
        self.feedRepository = feedRepository
        self.articleStateRepository = articleStateRepository
        self.articleQueryService = articleQueryService
    }

    func fetchSnapshot() throws -> SourcesSidebarSnapshotDTO {
        let baseFeeds = try feedRepository.fetchSidebarItems()
        let unreadCounts = try articleStateRepository.fetchUnreadCounts(feedIDs: baseFeeds.map(\.id))
        let feeds = baseFeeds.map { feed in
            feed.withUnreadCount(unreadCounts[feed.id, default: 0])
        }

        let starredItems = try articleQueryService.fetchInboxListItems(
            sortMode: .publishedAtDescending,
            filter: .starred
        )

        return SourcesSidebarSnapshotDTO(
            feeds: feeds,
            unreadSmartCount: feeds.reduce(0) { $0 + $1.unreadCount },
            starredSmartCount: starredItems.count,
            starredFeedIDs: Set(starredItems.map(\.feedID))
        )
    }
}
