import Foundation
@testable import RSSReader

@MainActor
final class CountingFeedRepository: FeedRepository {
    private let backing: any FeedRepository

    private(set) var fetchRequestCount = 0
    private(set) var updateMetadataCallCount = 0
    private(set) var saveAfterUpdateRequestCount = 0
    private(set) var explicitSaveRequestCount = 0

    var saveRequestCount: Int {
        saveAfterUpdateRequestCount + explicitSaveRequestCount
    }

    init(backing: any FeedRepository) {
        self.backing = backing
    }

    func fetchFeed(id: UUID) throws -> Feed? {
        fetchRequestCount += 1
        return try backing.fetchFeed(id: id)
    }

    func fetchFeed(url: String) throws -> Feed? {
        fetchRequestCount += 1
        return try backing.fetchFeed(url: url)
    }

    func fetchAllFeeds() throws -> [Feed] {
        fetchRequestCount += 1
        return try backing.fetchAllFeeds()
    }

    func fetchRetentionFeedIDBatch(offset: Int, limit: Int) throws -> [UUID] {
        fetchRequestCount += 1
        return try backing.fetchRetentionFeedIDBatch(offset: offset, limit: limit)
    }

    func fetchActiveFeeds() throws -> [Feed] {
        fetchRequestCount += 1
        return try backing.fetchActiveFeeds()
    }

    func countFeeds(inFolderID folderID: UUID?) throws -> Int {
        fetchRequestCount += 1
        return try backing.countFeeds(inFolderID: folderID)
    }

    func fetchSidebarItems() throws -> [FeedSidebarItem] {
        fetchRequestCount += 1
        return try backing.fetchSidebarItems()
    }

    func fetchMetadata(for feedID: UUID) throws -> FeedFetchMetadata? {
        fetchRequestCount += 1
        return try backing.fetchMetadata(for: feedID)
    }

    @discardableResult
    func insert(_ feed: Feed) throws -> Feed {
        try backing.insert(feed)
    }

    @discardableResult
    func updateMetadata(
        for feedID: UUID,
        with update: FeedMetadataUpdate,
        saveAfterOperation: Bool
    ) throws -> Feed? {
        updateMetadataCallCount += 1
        if saveAfterOperation {
            saveAfterUpdateRequestCount += 1
        }
        return try backing.updateMetadata(
            for: feedID,
            with: update,
            saveAfterOperation: saveAfterOperation
        )
    }

    @discardableResult
    func updateDetails(
        for feedID: UUID,
        with update: FeedDetailsUpdate,
        saveAfterOperation: Bool
    ) throws -> Feed? {
        if saveAfterOperation {
            saveAfterUpdateRequestCount += 1
        }
        return try backing.updateDetails(
            for: feedID,
            with: update,
            saveAfterOperation: saveAfterOperation
        )
    }

    @discardableResult
    func updateFolderAssignment(
        for feedID: UUID,
        with update: FeedFolderAssignmentUpdate,
        saveAfterOperation: Bool
    ) throws -> Feed? {
        if saveAfterOperation {
            saveAfterUpdateRequestCount += 1
        }
        return try backing.updateFolderAssignment(
            for: feedID,
            with: update,
            saveAfterOperation: saveAfterOperation
        )
    }

    @discardableResult
    func delete(feedID: UUID) throws -> Bool {
        try backing.delete(feedID: feedID)
    }

    func save() throws {
        explicitSaveRequestCount += 1
        try backing.save()
    }

    func rollback() {
        backing.rollback()
    }

    func delete(_ feed: Feed) throws {
        try backing.delete(feed)
    }
}

@MainActor
final class CountingArticleRepository: ArticleRepository {
    private let backing: any ArticleRepository

    private(set) var feedScopedFetchRequestCount = 0
    private(set) var identityFetchRequestCount = 0
    private(set) var reconcileFeedSnapshotCallCount = 0
    private(set) var saveRequestCount = 0

    init(backing: any ArticleRepository) {
        self.backing = backing
    }

    func refreshFeedProjection(for feed: Feed, saveAfterOperation: Bool) throws -> Int {
        feedScopedFetchRequestCount += 1
        if saveAfterOperation {
            saveRequestCount += 1
        }
        return try backing.refreshFeedProjection(for: feed, saveAfterOperation: saveAfterOperation)
    }

    func reconcileFeedSnapshot(
        _ payloads: [ArticleUpsertPayload],
        into feed: Feed,
        fetchedAt: Date,
        saveAfterOperation: Bool
    ) throws -> ArticleFeedSnapshotReconciliationResult {
        feedScopedFetchRequestCount += 1
        reconcileFeedSnapshotCallCount += 1
        if saveAfterOperation {
            saveRequestCount += 1
        }
        return try backing.reconcileFeedSnapshot(
            payloads,
            into: feed,
            fetchedAt: fetchedAt,
            saveAfterOperation: saveAfterOperation
        )
    }

    func fetchArticle(id: UUID) throws -> Article? {
        identityFetchRequestCount += 1
        return try backing.fetchArticle(id: id)
    }

    func fetchArticle(feedID: UUID, externalID: String) throws -> Article? {
        identityFetchRequestCount += 1
        return try backing.fetchArticle(feedID: feedID, externalID: externalID)
    }

    func containsArticle(feedID: UUID, externalID: String) throws -> Bool {
        identityFetchRequestCount += 1
        return try backing.containsArticle(feedID: feedID, externalID: externalID)
    }

    func fetchArticles(feedID: UUID) throws -> [Article] {
        feedScopedFetchRequestCount += 1
        return try backing.fetchArticles(feedID: feedID)
    }

    func fetchArticles(feedID: UUID, sortMode: ArticleSortMode) throws -> [Article] {
        feedScopedFetchRequestCount += 1
        return try backing.fetchArticles(feedID: feedID, sortMode: sortMode)
    }

    func fetchInbox(sortMode: ArticleSortMode) throws -> [Article] {
        feedScopedFetchRequestCount += 1
        return try backing.fetchInbox(sortMode: sortMode)
    }

    func fetchArchivedArticles() throws -> [Article] {
        feedScopedFetchRequestCount += 1
        return try backing.fetchArchivedArticles()
    }

    func fetchRetentionBatch(
        feedID: UUID,
        scope: ArticleRetentionBatchScope,
        offset: Int,
        limit: Int
    ) throws -> [Article] {
        feedScopedFetchRequestCount += 1
        return try backing.fetchRetentionBatch(
            feedID: feedID,
            scope: scope,
            offset: offset,
            limit: limit
        )
    }

    func reconcileArticles(
        feedID: UUID,
        keepingExternalIDs: Set<String>,
        fetchedAt: Date,
        saveAfterOperation: Bool
    ) throws -> Int {
        feedScopedFetchRequestCount += 1
        if saveAfterOperation {
            saveRequestCount += 1
        }
        return try backing.reconcileArticles(
            feedID: feedID,
            keepingExternalIDs: keepingExternalIDs,
            fetchedAt: fetchedAt,
            saveAfterOperation: saveAfterOperation
        )
    }

    @discardableResult
    func upsert(_ entry: ParsedFeedEntryDTO, into feed: Feed, fetchedAt: Date) throws -> Article? {
        try backing.upsert(entry, into: feed, fetchedAt: fetchedAt)
    }

    @discardableResult
    func upsert(
        _ entries: [ParsedFeedEntryDTO],
        into feed: Feed,
        fetchedAt: Date,
        saveAfterOperation: Bool
    ) throws -> [Article] {
        if saveAfterOperation {
            saveRequestCount += 1
        }
        return try backing.upsert(
            entries,
            into: feed,
            fetchedAt: fetchedAt,
            saveAfterOperation: saveAfterOperation
        )
    }

    @discardableResult
    func upsert(_ payload: ArticleUpsertPayload, into feed: Feed) throws -> Article {
        try backing.upsert(payload, into: feed)
    }

    @discardableResult
    func upsert(
        _ payloads: [ArticleUpsertPayload],
        into feed: Feed,
        saveAfterOperation: Bool
    ) throws -> [Article] {
        if saveAfterOperation {
            saveRequestCount += 1
        }
        return try backing.upsert(
            payloads,
            into: feed,
            saveAfterOperation: saveAfterOperation
        )
    }

    func save() throws {
        saveRequestCount += 1
        try backing.save()
    }

    func delete(_ article: Article) throws {
        try backing.delete(article)
    }

    func delete(_ articles: [Article], saveAfterOperation: Bool) throws {
        if saveAfterOperation {
            saveRequestCount += 1
        }
        try backing.delete(articles, saveAfterOperation: saveAfterOperation)
    }
}
