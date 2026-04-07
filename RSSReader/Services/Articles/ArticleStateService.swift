import Foundation

@MainActor
protocol ArticleStateServicing {
    func fetchStateSnapshot(feedID: UUID, articleExternalID: String) throws -> ArticleUserStateSnapshot?
    func fetchStateSnapshots(for articles: [Article]) throws -> [String: ArticleUserStateSnapshot]
    func fetchUnreadCounts(feedIDs: [UUID]) throws -> [UUID: Int]
}

@MainActor
final class ArticleStateService: ArticleStateServicing {
    private let logger: Logging
    private let articleStateRepository: any ArticleStateRepository

    init(
        logger: Logging,
        articleStateRepository: any ArticleStateRepository
    ) {
        self.logger = logger
        self.articleStateRepository = articleStateRepository
    }

    func fetchStateSnapshot(feedID: UUID, articleExternalID: String) throws -> ArticleUserStateSnapshot? {
        try articleStateRepository.fetchStateSnapshot(
            feedID: feedID,
            articleExternalID: articleExternalID
        )
    }

    func fetchStateSnapshots(for articles: [Article]) throws -> [String: ArticleUserStateSnapshot] {
        guard articles.isEmpty == false else { return [:] }

        let snapshots = try articleStateRepository.fetchStateSnapshots(for: articles)
        logger.debug("Fetched article state snapshots for \(articles.count) articles")
        return snapshots
    }

    func fetchUnreadCounts(feedIDs: [UUID]) throws -> [UUID: Int] {
        guard feedIDs.isEmpty == false else { return [:] }

        let unreadCounts = try articleStateRepository.fetchUnreadCounts(feedIDs: feedIDs)
        logger.debug("Fetched unread counts for \(feedIDs.count) feeds")
        return unreadCounts
    }
}
