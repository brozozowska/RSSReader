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
        let starredCountsByFeedID = try fetchStarredCountsByFeedID()
        let feeds = baseFeeds.map { feed in
            feed.withCounts(
                unreadCount: unreadCounts[feed.id, default: 0],
                starredCount: starredCountsByFeedID[feed.id, default: 0]
            )
        }

        return SourcesSidebarSnapshotDTO(
            feeds: feeds,
            unreadSmartCount: feeds.reduce(0) { $0 + $1.unreadCount },
            starredSmartCount: feeds.reduce(0) { $0 + $1.starredCount },
            starredFeedIDs: Set(feeds.filter { $0.starredCount > 0 }.map(\.id))
        )
    }

    private func fetchStarredCountsByFeedID() throws -> [UUID: Int] {
        let starredItems = try articleQueryService.fetchInboxListItems(
            sortMode: .publishedAtDescending,
            filter: .starred
        )

        return starredItems.reduce(into: [UUID: Int]()) { partialResult, item in
            partialResult[item.feedID, default: 0] += 1
        }
    }
}
