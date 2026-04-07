import Foundation

@MainActor
protocol ArticleStateServicing {
    func fetchStateSnapshot(feedID: UUID, articleExternalID: String) throws -> ArticleUserStateSnapshot?
    func fetchStateSnapshots(for articles: [Article]) throws -> [String: ArticleUserStateSnapshot]
    func fetchUnreadCounts(feedIDs: [UUID]) throws -> [UUID: Int]
    func markAsRead(feedID: UUID, articleExternalID: String, at: Date) throws -> ArticleUserStateSnapshot
    func markAsRead(article: Article, at: Date) throws -> ArticleUserStateSnapshot
    func markAsUnread(feedID: UUID, articleExternalID: String, at: Date) throws -> ArticleUserStateSnapshot
    func markAsUnread(article: Article, at: Date) throws -> ArticleUserStateSnapshot
    func toggleStarred(feedID: UUID, articleExternalID: String, at: Date) throws -> ArticleUserStateSnapshot
    func toggleStarred(article: Article, at: Date) throws -> ArticleUserStateSnapshot
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

    func markAsRead(
        feedID: UUID,
        articleExternalID: String,
        at: Date = .now
    ) throws -> ArticleUserStateSnapshot {
        let articleState = try articleStateRepository.upsert(
            feedID: feedID,
            articleExternalID: articleExternalID,
            update: ArticleStateUpsert(
                isRead: true,
                readAt: at,
                lastInteractionAt: at,
                updatedAt: at
            )
        )
        logger.info("Marked article as read for feed \(feedID.uuidString)")
        return ArticleUserStateSnapshot(articleState: articleState)
    }

    func markAsRead(article: Article, at: Date = .now) throws -> ArticleUserStateSnapshot {
        try markAsRead(
            feedID: article.feedID,
            articleExternalID: article.externalID,
            at: at
        )
    }

    func markAsUnread(
        feedID: UUID,
        articleExternalID: String,
        at: Date = .now
    ) throws -> ArticleUserStateSnapshot {
        let articleState = try articleStateRepository.upsert(
            feedID: feedID,
            articleExternalID: articleExternalID,
            update: ArticleStateUpsert(
                isRead: false,
                readAt: nil,
                lastInteractionAt: at,
                updatedAt: at
            )
        )
        logger.info("Marked article as unread for feed \(feedID.uuidString)")
        return ArticleUserStateSnapshot(articleState: articleState)
    }

    func markAsUnread(article: Article, at: Date = .now) throws -> ArticleUserStateSnapshot {
        try markAsUnread(
            feedID: article.feedID,
            articleExternalID: article.externalID,
            at: at
        )
    }

    func toggleStarred(
        feedID: UUID,
        articleExternalID: String,
        at: Date = .now
    ) throws -> ArticleUserStateSnapshot {
        let currentState = try articleStateRepository.fetchStateSnapshot(
            feedID: feedID,
            articleExternalID: articleExternalID
        )
        let newIsStarred = (currentState?.isStarred ?? false) == false
        let articleState = try articleStateRepository.upsert(
            feedID: feedID,
            articleExternalID: articleExternalID,
            update: ArticleStateUpsert(
                isStarred: newIsStarred,
                starredAt: newIsStarred ? at : nil,
                lastInteractionAt: at,
                updatedAt: at
            )
        )
        logger.info("Toggled starred state for article in feed \(feedID.uuidString)")
        return ArticleUserStateSnapshot(articleState: articleState)
    }

    func toggleStarred(article: Article, at: Date = .now) throws -> ArticleUserStateSnapshot {
        try toggleStarred(
            feedID: article.feedID,
            articleExternalID: article.externalID,
            at: at
        )
    }
}
