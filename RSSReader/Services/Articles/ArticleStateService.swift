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
    func markAllVisibleAsRead(feedID: UUID, articleExternalIDs: [String], at: Date) throws -> [ArticleUserStateSnapshot]
    func markAllVisibleAsRead(_ items: [ArticleListItemDTO], at: Date) throws -> [ArticleUserStateSnapshot]
    func markAllVisibleAsRead(_ articles: [Article], at: Date) throws -> [ArticleUserStateSnapshot]
    func markAllMatchingAsRead(
        request: ArticleSearchRequest,
        articleQueryService: any ArticleQueryService,
        at: Date
    ) async throws -> ArticleScopeReadMutationResult
}

struct ArticleScopeReadMutationResult: Equatable, Sendable {
    let processedIdentityCount: Int
    let persistedReadCount: Int
    let rejectedIdentityCount: Int
    let processedBatchCount: Int
}

@MainActor
final class ArticleStateService: ArticleStateServicing {
    private let logger: Logging
    private let articleStateRepository: any ArticleStateRepository
    private let unreadAppIconBadgeService: (any UnreadAppIconBadgeServicing)?

    init(
        logger: Logging,
        articleStateRepository: any ArticleStateRepository,
        unreadAppIconBadgeService: (any UnreadAppIconBadgeServicing)? = nil
    ) {
        self.logger = logger
        self.articleStateRepository = articleStateRepository
        self.unreadAppIconBadgeService = unreadAppIconBadgeService
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
            update: makeReadUpdate(isRead: true, at: at)
        )
        logger.info("Marked article as read for feed \(feedID.uuidString)")
        scheduleUnreadAppIconBadgeRefresh()
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
            update: makeReadUpdate(isRead: false, at: at)
        )
        logger.info("Marked article as unread for feed \(feedID.uuidString)")
        scheduleUnreadAppIconBadgeRefresh()
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
            update: makeStarredUpdate(isStarred: newIsStarred, at: at)
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

    func markAllVisibleAsRead(
        feedID: UUID,
        articleExternalIDs: [String],
        at: Date = .now
    ) throws -> [ArticleUserStateSnapshot] {
        guard articleExternalIDs.isEmpty == false else { return [] }

        let articleStates = try articleStateRepository.bulkSetRead(
            feedID: feedID,
            articleExternalIDs: articleExternalIDs,
            isRead: true,
            at: at
        )
        logger.info("Marked \(articleStates.count) visible articles as read for feed \(feedID.uuidString)")
        scheduleUnreadAppIconBadgeRefresh()
        return articleStates.map(ArticleUserStateSnapshot.init(articleState:))
    }

    func markAllVisibleAsRead(
        _ items: [ArticleListItemDTO],
        at: Date = .now
    ) throws -> [ArticleUserStateSnapshot] {
        guard items.isEmpty == false else { return [] }

        let itemsByFeedID = Dictionary(grouping: items, by: \.feedID)
        return try itemsByFeedID
            .keys
            .sorted { $0.uuidString < $1.uuidString }
            .flatMap { feedID in
                let articleExternalIDs = itemsByFeedID[feedID, default: []].map(\.articleExternalID)
                return try markAllVisibleAsRead(
                    feedID: feedID,
                    articleExternalIDs: articleExternalIDs,
                    at: at
                )
            }
    }

    func markAllVisibleAsRead(
        _ articles: [Article],
        at: Date = .now
    ) throws -> [ArticleUserStateSnapshot] {
        guard articles.isEmpty == false else { return [] }

        let articlesByFeedID = Dictionary(grouping: articles, by: \.feedID)
        return try articlesByFeedID
            .keys
            .sorted { $0.uuidString < $1.uuidString }
            .flatMap { feedID in
                let articleExternalIDs = articlesByFeedID[feedID, default: []].map(\.externalID)
                return try markAllVisibleAsRead(
                    feedID: feedID,
                    articleExternalIDs: articleExternalIDs,
                    at: at
                )
            }
    }

    func markAllMatchingAsRead(
        request: ArticleSearchRequest,
        articleQueryService: any ArticleQueryService,
        at: Date = .now
    ) async throws -> ArticleScopeReadMutationResult {
        precondition(request.limit > 0)

        var cursor = request.cursor
        var processedIdentityCount = 0
        var persistedReadCount = 0
        var processedBatchCount = 0
        var didPersistMutation = false

        defer {
            if didPersistMutation {
                scheduleUnreadAppIconBadgeRefresh()
            }
        }

        repeat {
            try Task.checkCancellation()
            let batchRequest = ArticleSearchRequest(
                selection: request.selection,
                sidebarArticleFilter: request.sidebarArticleFilter,
                query: request.normalizedQuery,
                sortMode: request.sortMode,
                limit: request.limit,
                cursor: cursor,
                emptyQueryBehavior: request.emptyQueryBehavior,
                requiresUnread: true
            )
            let snapshot = try await articleQueryService.fetchArticleSearchSnapshot(batchRequest)
            try Task.checkCancellation()

            if snapshot.articles.isEmpty == false {
                processedBatchCount += 1
            }
            let identitiesByFeedID = Dictionary(grouping: snapshot.articles, by: \.feedID)
            for feedID in identitiesByFeedID.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
                try Task.checkCancellation()
                let externalIDs = identitiesByFeedID[feedID, default: []].map(\.articleExternalID)
                let states = try articleStateRepository.bulkSetRead(
                    feedID: feedID,
                    articleExternalIDs: externalIDs,
                    isRead: true,
                    at: at
                )
                didPersistMutation = didPersistMutation || states.isEmpty == false
                processedIdentityCount += externalIDs.count
                persistedReadCount += states.lazy.filter(\.isRead).count
            }

            guard let nextCursor = snapshot.nextCursor else { break }
            guard nextCursor != cursor else { break }
            cursor = nextCursor
            try Task.checkCancellation()
            await Task.yield()
        } while true

        logger.info(
            "Marked \(persistedReadCount) of \(processedIdentityCount) matching articles as read in \(processedBatchCount) batches"
        )
        return ArticleScopeReadMutationResult(
            processedIdentityCount: processedIdentityCount,
            persistedReadCount: persistedReadCount,
            rejectedIdentityCount: processedIdentityCount - persistedReadCount,
            processedBatchCount: processedBatchCount
        )
    }

    private func makeReadUpdate(isRead: Bool, at: Date) -> ArticleStateUpsert {
        ArticleStateUpsert(
            isRead: isRead,
            readAt: isRead ? at : nil,
            lastInteractionAt: at,
            updatedAt: at
        )
    }

    private func makeStarredUpdate(isStarred: Bool, at: Date) -> ArticleStateUpsert {
        ArticleStateUpsert(
            isStarred: isStarred,
            starredAt: isStarred ? at : nil,
            lastInteractionAt: at,
            updatedAt: at
        )
    }

    private func scheduleUnreadAppIconBadgeRefresh() {
        guard let unreadAppIconBadgeService else { return }

        Task { @MainActor in
            await unreadAppIconBadgeService.refreshBadgeCount()
        }
    }
}
