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

enum ArticleFeedSnapshotCancellationCheckpoint: Equatable, Sendable {
    case beforeSnapshot
    case beforeUpsert
    case afterUpsert
}

@MainActor
protocol ArticleRepository {
    func refreshFeedProjection(for feed: Feed, saveAfterOperation: Bool) throws -> Int
    func reconcileFeedSnapshot(
        _ payloads: [ArticleUpsertPayload],
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

    func save() throws
    func delete(_ article: Article) throws
    func delete(_ articles: [Article], saveAfterOperation: Bool) throws
}

extension ArticleRepository {
    func refreshFeedProjection(for feed: Feed) throws -> Int {
        try refreshFeedProjection(for: feed, saveAfterOperation: true)
    }

    func reconcileFeedSnapshot(
        _ payloads: [ArticleUpsertPayload],
        into feed: Feed,
        fetchedAt: Date
    ) throws -> ArticleFeedSnapshotReconciliationResult {
        try reconcileFeedSnapshot(
            payloads,
            into: feed,
            fetchedAt: fetchedAt,
            saveAfterOperation: true
        )
    }

    func delete(_ articles: [Article]) throws {
        try delete(articles, saveAfterOperation: true)
    }
}

@MainActor
final class SwiftDataArticleRepository: ArticleRepository, SwiftDataRepositoryContext {
    let modelContext: ModelContext
    let persistenceOperationRecorder: SwiftDataRepositoryOperationRecorder
    private let cancellationCheckpoint: (ArticleFeedSnapshotCancellationCheckpoint) throws -> Void

    init(
        modelContext: ModelContext,
        persistenceOperationRecorder: @escaping SwiftDataRepositoryOperationRecorder = { _ in },
        cancellationCheckpoint: @escaping (ArticleFeedSnapshotCancellationCheckpoint) throws -> Void = { _ in
            try Task.checkCancellation()
        }
    ) {
        self.modelContext = modelContext
        self.persistenceOperationRecorder = persistenceOperationRecorder
        self.cancellationCheckpoint = cancellationCheckpoint
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
        _ payloads: [ArticleUpsertPayload],
        into feed: Feed,
        fetchedAt: Date,
        saveAfterOperation: Bool = true
    ) throws -> ArticleFeedSnapshotReconciliationResult {
        try cancellationCheckpoint(.beforeSnapshot)
        let incomingIdentities = Set(
            payloads.map { normalizedArticleIdentity($0.externalID) }
        )
        let existingArticles = try fetchArticles(feedID: feed.id)
        let canonicalSnapshot = canonicalArticleSnapshot(
            from: existingArticles
        )
        var articlesByIdentity = canonicalSnapshot.articlesByIdentity
        var projectionUpdateCount = 0
        var reconciledArticleCount = 0

        for (identity, article) in articlesByIdentity {
            if canonicalSnapshot.duplicateIdentities.contains(identity),
               article.externalID != identity {
                article.externalID = identity
                article.updatedAt = .now
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

        for duplicateArticle in canonicalSnapshot.duplicateArticles {
            modelContext.delete(duplicateArticle)
        }

        try cancellationCheckpoint(.beforeUpsert)
        let upsertedArticles = applyPayloads(
            payloads,
            into: feed,
            articlesByIdentity: &articlesByIdentity
        )
        try cancellationCheckpoint(.afterUpsert)

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
        return try performFetchCount(descriptor) > 0
    }

    func fetchArticles(feedID: UUID) throws -> [Article] {
        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { article in
                article.feedID == feedID
            }
        )
        return try performFetch(descriptor)
    }

    func fetchArticles(feedID: UUID, sortMode: ArticleSortMode) throws -> [Article] {
        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { article in
                article.feedID == feedID
            },
            sortBy: sortDescriptors(for: sortMode)
        )
        return try performFetch(descriptor)
    }

    func fetchInbox(sortMode: ArticleSortMode) throws -> [Article] {
        let descriptor = FetchDescriptor<Article>(
            sortBy: sortDescriptors(for: sortMode)
        )
        return try performFetch(descriptor)
    }

    func fetchArchivedArticles() throws -> [Article] {
        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { article in
                article.archivedAt != nil
            }
        )
        return try performFetch(descriptor)
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
        return try performFetch(descriptor)
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

    private func applyPayloads(
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

    private func canonicalArticleSnapshot(
        from articles: [Article]
    ) -> (
        articlesByIdentity: [String: Article],
        duplicateArticles: [Article],
        duplicateIdentities: Set<String>
    ) {
        var articlesByIdentity: [String: Article] = [:]
        var duplicateArticles: [Article] = []
        var duplicateIdentities: Set<String> = []

        for article in articles {
            let identity = normalizedArticleIdentity(article.externalID)
            guard let existingCanonicalArticle = articlesByIdentity[identity] else {
                articlesByIdentity[identity] = article
                continue
            }

            duplicateIdentities.insert(identity)
            if articleCanonicalOrder(article, existingCanonicalArticle) {
                articlesByIdentity[identity] = article
                duplicateArticles.append(existingCanonicalArticle)
            } else {
                duplicateArticles.append(article)
            }
        }

        return (articlesByIdentity, duplicateArticles, duplicateIdentities)
    }

    private func articleCanonicalOrder(_ lhs: Article, _ rhs: Article) -> Bool {
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }

        return lhs.id.uuidString > rhs.id.uuidString
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
