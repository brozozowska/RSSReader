import Foundation
import SwiftData

enum ArticleRetentionBatchScope: Sendable {
    case all
    case archived
}

struct ArticleFeedSnapshotReconciliationResult {
    let projectionUpdateCount: Int
    let reconciledArticleCount: Int
    let upsertedArticleCount: Int
}

@MainActor
protocol ArticleRepository {
    func refreshFeedProjection(for feed: Feed, saveAfterOperation: Bool) throws -> Int
    func reconcileFeedSnapshot(
        _ entries: [ParsedFeedEntryDTO],
        into feed: Feed,
        fetchedAt: Date,
        saveAfterOperation: Bool
    ) throws -> ArticleFeedSnapshotReconciliationResult
    func fetchArticle(id: UUID) throws -> Article?
    func fetchArticle(feedID: UUID, externalID: String) throws -> Article?
    func containsArticle(feedID: UUID, externalID: String) throws -> Bool
    func fetchArticles(feedID: UUID) throws -> [Article]
    func fetchArticles(feedID: UUID, sortMode: ArticleSortMode) throws -> [Article]
    func fetchInbox(sortMode: ArticleSortMode) throws -> [Article]
    func fetchArchivedArticles() throws -> [Article]
    func fetchRetentionBatch(
        feedID: UUID,
        scope: ArticleRetentionBatchScope,
        offset: Int,
        limit: Int
    ) throws -> [Article]
    func reconcileArticles(
        feedID: UUID,
        keepingExternalIDs: Set<String>,
        fetchedAt: Date,
        saveAfterOperation: Bool
    ) throws -> Int

    @discardableResult
    func upsert(_ entry: ParsedFeedEntryDTO, into feed: Feed, fetchedAt: Date) throws -> Article?

    @discardableResult
    func upsert(
        _ entries: [ParsedFeedEntryDTO],
        into feed: Feed,
        fetchedAt: Date,
        saveAfterOperation: Bool
    ) throws -> [Article]

    @discardableResult
    func upsert(_ payload: ArticleUpsertPayload, into feed: Feed) throws -> Article

    @discardableResult
    func upsert(
        _ payloads: [ArticleUpsertPayload],
        into feed: Feed,
        saveAfterOperation: Bool
    ) throws -> [Article]

    func save() throws
    func delete(_ article: Article) throws
    func delete(_ articles: [Article], saveAfterOperation: Bool) throws
}

extension ArticleRepository {
    func refreshFeedProjection(for feed: Feed) throws -> Int {
        try refreshFeedProjection(for: feed, saveAfterOperation: true)
    }

    func reconcileFeedSnapshot(
        _ entries: [ParsedFeedEntryDTO],
        into feed: Feed,
        fetchedAt: Date
    ) throws -> ArticleFeedSnapshotReconciliationResult {
        try reconcileFeedSnapshot(
            entries,
            into: feed,
            fetchedAt: fetchedAt,
            saveAfterOperation: true
        )
    }

    func reconcileArticles(feedID: UUID, keepingExternalIDs: Set<String>, fetchedAt: Date) throws -> Int {
        try reconcileArticles(
            feedID: feedID,
            keepingExternalIDs: keepingExternalIDs,
            fetchedAt: fetchedAt,
            saveAfterOperation: true
        )
    }

    @discardableResult
    func upsert(_ entries: [ParsedFeedEntryDTO], into feed: Feed, fetchedAt: Date) throws -> [Article] {
        try upsert(entries, into: feed, fetchedAt: fetchedAt, saveAfterOperation: true)
    }

    @discardableResult
    func upsert(_ payloads: [ArticleUpsertPayload], into feed: Feed) throws -> [Article] {
        try upsert(payloads, into: feed, saveAfterOperation: true)
    }

    func delete(_ articles: [Article]) throws {
        try delete(articles, saveAfterOperation: true)
    }
}

@MainActor
final class SwiftDataArticleRepository: ArticleRepository, SwiftDataRepositoryContext {
    let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func refreshFeedProjection(for feed: Feed, saveAfterOperation: Bool = true) throws -> Int {
        let articles = try fetchArticles(feedID: feed.id)
        let updatedCount = articles.reduce(into: 0) { updatedCount, article in
            updatedCount += updateFeedProjection(of: article, from: feed)
        }

        if updatedCount > 0, saveAfterOperation {
            try saveIfNeeded()
        }
        return updatedCount
    }

    func reconcileFeedSnapshot(
        _ entries: [ParsedFeedEntryDTO],
        into feed: Feed,
        fetchedAt: Date,
        saveAfterOperation: Bool = true
    ) throws -> ArticleFeedSnapshotReconciliationResult {
        try Task.checkCancellation()
        let payloads = try ArticleUpsertPayload.makeAll(
            entries: entries,
            fetchedAt: fetchedAt
        )
        let incomingIdentities = Set(
            payloads.map { normalizedArticleIdentity($0.externalID) }
        )
        let existingArticles = try fetchArticles(feedID: feed.id)
        var articlesByIdentity: [String: Article] = [:]
        var projectionUpdateCount = 0
        var reconciledArticleCount = 0

        for article in existingArticles {
            let identity = normalizedArticleIdentity(article.externalID)
            if articlesByIdentity[identity] == nil {
                articlesByIdentity[identity] = article
            }

            projectionUpdateCount += updateFeedProjection(of: article, from: feed)
            if reconcileArchiveState(
                of: article,
                keepingIdentities: incomingIdentities,
                fetchedAt: fetchedAt
            ) {
                reconciledArticleCount += 1
            }
        }

        try Task.checkCancellation()
        let upsertedArticles = upsert(
            payloads,
            into: feed,
            articlesByIdentity: &articlesByIdentity
        )
        try Task.checkCancellation()

        if saveAfterOperation {
            try saveIfNeeded()
        }

        return ArticleFeedSnapshotReconciliationResult(
            projectionUpdateCount: projectionUpdateCount,
            reconciledArticleCount: reconciledArticleCount,
            upsertedArticleCount: upsertedArticles.count
        )
    }

    func fetchArticle(id: UUID) throws -> Article? {
        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { article in
                article.id == id
            }
        )
        return try fetchFirst(descriptor)
    }

    func fetchArticle(feedID: UUID, externalID: String) throws -> Article? {
        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { article in
                article.feedID == feedID && article.externalID == externalID
            }
        )
        return try fetchFirst(descriptor)
    }

    func containsArticle(feedID: UUID, externalID: String) throws -> Bool {
        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { article in
                article.feedID == feedID && article.externalID == externalID
            }
        )
        return try modelContext.fetchCount(descriptor) > 0
    }

    func fetchArticles(feedID: UUID) throws -> [Article] {
        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { article in
                article.feedID == feedID
            }
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchArticles(feedID: UUID, sortMode: ArticleSortMode) throws -> [Article] {
        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { article in
                article.feedID == feedID
            },
            sortBy: sortDescriptors(for: sortMode)
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchInbox(sortMode: ArticleSortMode) throws -> [Article] {
        let descriptor = FetchDescriptor<Article>(
            sortBy: sortDescriptors(for: sortMode)
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchArchivedArticles() throws -> [Article] {
        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { article in
                article.archivedAt != nil
            }
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchRetentionBatch(
        feedID: UUID,
        scope: ArticleRetentionBatchScope,
        offset: Int,
        limit: Int
    ) throws -> [Article] {
        precondition(offset >= 0)
        precondition(limit > 0)

        var descriptor: FetchDescriptor<Article>
        switch scope {
        case .all:
            descriptor = FetchDescriptor<Article>(
                predicate: #Predicate<Article> { article in
                    article.feedID == feedID
                },
                sortBy: retentionBatchSortDescriptors
            )
        case .archived:
            descriptor = FetchDescriptor<Article>(
                predicate: #Predicate<Article> { article in
                    article.feedID == feedID && article.archivedAt != nil
                },
                sortBy: retentionBatchSortDescriptors
            )
        }
        descriptor.fetchOffset = offset
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor)
    }

    @discardableResult
    func upsert(_ entry: ParsedFeedEntryDTO, into feed: Feed, fetchedAt: Date = .now) throws -> Article? {
        guard let payload = ArticleUpsertPayload(entry: entry, fetchedAt: fetchedAt) else {
            return nil
        }

        return try upsert(payload, into: feed)
    }

    @discardableResult
    func upsert(
        _ entries: [ParsedFeedEntryDTO],
        into feed: Feed,
        fetchedAt: Date = .now,
        saveAfterOperation: Bool = true
    ) throws -> [Article] {
        let payloads = try ArticleUpsertPayload.makeAll(
            entries: entries,
            fetchedAt: fetchedAt
        )
        return try upsert(payloads, into: feed, saveAfterOperation: saveAfterOperation)
    }

    @discardableResult
    func upsert(_ payload: ArticleUpsertPayload, into feed: Feed) throws -> Article {
        try upsert([payload], into: feed, saveAfterOperation: true)[0]
    }

    @discardableResult
    func upsert(
        _ payloads: [ArticleUpsertPayload],
        into feed: Feed,
        saveAfterOperation: Bool = true
    ) throws -> [Article] {
        let existingArticles = try fetchArticles(feedID: feed.id)
        var articlesByIdentity = existingArticles.reduce(into: [String: Article]()) { articlesByIdentity, article in
            let identity = normalizedArticleIdentity(article.externalID)
            if articlesByIdentity[identity] == nil {
                articlesByIdentity[identity] = article
            }
        }
        let upsertedArticles = upsert(
            payloads,
            into: feed,
            articlesByIdentity: &articlesByIdentity
        )

        if saveAfterOperation {
            try saveIfNeeded()
        }
        return upsertedArticles
    }

    func save() throws {
        try saveIfNeeded(force: true)
    }

    func delete(_ article: Article) throws {
        modelContext.delete(article)
        try saveIfNeeded()
    }

    func delete(_ articles: [Article], saveAfterOperation: Bool = true) throws {
        guard articles.isEmpty == false else { return }

        for article in articles {
            modelContext.delete(article)
        }

        if saveAfterOperation {
            try saveIfNeeded()
        }
    }

    func reconcileArticles(
        feedID: UUID,
        keepingExternalIDs: Set<String>,
        fetchedAt: Date,
        saveAfterOperation: Bool = true
    ) throws -> Int {
        let normalizedExternalIDs = Set(keepingExternalIDs.compactMap(normalizedIdentifier))
        let articles = try fetchArticles(feedID: feedID)
        var reconciledCount = 0

        for article in articles {
            if reconcileArchiveState(
                of: article,
                keepingIdentities: normalizedExternalIDs,
                fetchedAt: fetchedAt
            ) {
                reconciledCount += 1
            }
        }

        if saveAfterOperation {
            try saveIfNeeded()
        }
        return reconciledCount
    }

    private func updateFeedProjection(of article: Article, from feed: Feed) -> Int {
        var updatedCount = 0

        if article.feedTitle != feed.displayTitle {
            article.feedTitle = feed.displayTitle
            updatedCount += 1
        }

        if article.feedSiteURL != feed.siteURL {
            article.feedSiteURL = feed.siteURL
            updatedCount += 1
        }

        let folderName = feed.folder?.name
        if article.feedFolderName != folderName {
            article.feedFolderName = folderName
            updatedCount += 1
        }

        return updatedCount
    }

    private func reconcileArchiveState(
        of article: Article,
        keepingIdentities: Set<String>,
        fetchedAt: Date
    ) -> Bool {
        let identity = normalizedArticleIdentity(article.externalID)
        let shouldKeep = keepingIdentities.contains(identity)
        let newArchivedAt = shouldKeep ? nil : (article.archivedAt ?? fetchedAt)

        guard article.archivedAt != newArchivedAt else { return false }

        article.archivedAt = newArchivedAt
        article.fetchedAt = fetchedAt
        article.updatedAt = .now
        return true
    }

    private func upsert(
        _ payloads: [ArticleUpsertPayload],
        into feed: Feed,
        articlesByIdentity: inout [String: Article]
    ) -> [Article] {
        var upsertedArticles: [Article] = []
        var upsertedIdentities: Set<String> = []

        for payload in payloads {
            let identity = normalizedArticleIdentity(payload.externalID)
            let article: Article

            if let existingArticle = articlesByIdentity[identity] {
                apply(payload, to: existingArticle)
                article = existingArticle
            } else {
                article = makeArticle(from: payload, feed: feed)
                modelContext.insert(article)
                articlesByIdentity[identity] = article
            }

            if upsertedIdentities.insert(identity).inserted {
                upsertedArticles.append(article)
            }
        }

        return upsertedArticles
    }

    private func apply(_ payload: ArticleUpsertPayload, to article: Article) {
        article.guid = payload.guid
        article.url = payload.url
        article.canonicalURL = payload.canonicalURL
        article.title = payload.title
        article.summary = payload.summary
        article.contentHTML = payload.contentHTML
        article.contentText = payload.contentText
        article.author = payload.author
        article.publishedAt = payload.publishedAt
        article.updatedAtSource = payload.updatedAtSource
        article.imageURL = payload.imageURL
        article.archivedAt = payload.archivedAt
        article.fetchedAt = payload.fetchedAt
        article.updatedAt = .now
    }

    private func makeArticle(from payload: ArticleUpsertPayload, feed: Feed) -> Article {
        Article(
            feedID: feed.id,
            feedTitle: feed.displayTitle,
            feedSiteURL: feed.siteURL,
            feedFolderName: feed.folder?.name,
            externalID: payload.externalID,
            guid: payload.guid,
            url: payload.url,
            canonicalURL: payload.canonicalURL,
            title: payload.title,
            summary: payload.summary,
            contentHTML: payload.contentHTML,
            contentText: payload.contentText,
            author: payload.author,
            publishedAt: payload.publishedAt,
            updatedAtSource: payload.updatedAtSource,
            imageURL: payload.imageURL,
            archivedAt: payload.archivedAt,
            fetchedAt: payload.fetchedAt
        )
    }

    private func normalizedArticleIdentity(_ externalID: String) -> String {
        normalizedIdentifier(externalID) ?? externalID
    }

    private func sortDescriptors(for sortMode: ArticleSortMode) -> [SortDescriptor<Article>] {
        switch sortMode {
        case .publishedAtDescending:
            [
                SortDescriptor(\Article.publishedAt, order: .reverse),
                SortDescriptor(\Article.fetchedAt, order: .reverse)
            ]
        case .publishedAtAscending:
            [
                SortDescriptor(\Article.publishedAt, order: .forward),
                SortDescriptor(\Article.fetchedAt, order: .forward)
            ]
        }
    }

    private var retentionBatchSortDescriptors: [SortDescriptor<Article>] {
        [
            SortDescriptor(\Article.createdAt, order: .forward),
            SortDescriptor(\Article.id, order: .forward)
        ]
    }
}
