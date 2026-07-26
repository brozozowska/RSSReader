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

enum ArticleFeedSnapshotReconciliationStage: CaseIterable, Hashable, Sendable {
    case incomingIdentityMaterialization
    case snapshotCanonicalization
    case articleStateMaterialization
    case articleStateCanonicalization
    case articleStateDuplicateDeletion
    case projectionAndArchive
    case duplicateDeletion
    case payloadApply
}

struct ArticleFeedSnapshotReconciliationProgress: Sendable {
    let stage: ArticleFeedSnapshotReconciliationStage
    let processedItemCount: Int
    let totalItemCount: Int
}

typealias ArticleFeedSnapshotReconciliationProgressProbe = @MainActor (
    ArticleFeedSnapshotReconciliationProgress
) -> Void

enum ArticleFeedSnapshotCancellationCheckpoint: Equatable, Sendable {
    case beforeSnapshot
    case during(ArticleFeedSnapshotReconciliationStage)
    case beforeUpsert
    case afterUpsert
}

enum ArticleFeedSnapshotReconciliationPolicy {
    static let cancellationCheckpointInterval = 32
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
    private let reconciliationProgressProbe: ArticleFeedSnapshotReconciliationProgressProbe?
    private let articleStateIdentityRepairer: SwiftDataArticleStateIdentityRepairer

    init(
        modelContext: ModelContext,
        persistenceOperationRecorder: @escaping SwiftDataRepositoryOperationRecorder = { _ in },
        cancellationCheckpoint: @escaping (ArticleFeedSnapshotCancellationCheckpoint) throws -> Void = { _ in
            try Task.checkCancellation()
        },
        reconciliationProgressProbe: ArticleFeedSnapshotReconciliationProgressProbe? = nil
    ) {
        self.modelContext = modelContext
        self.persistenceOperationRecorder = persistenceOperationRecorder
        self.cancellationCheckpoint = cancellationCheckpoint
        self.reconciliationProgressProbe = reconciliationProgressProbe
        self.articleStateIdentityRepairer = SwiftDataArticleStateIdentityRepairer(
            modelContext: modelContext,
            persistenceOperationRecorder: persistenceOperationRecorder
        )
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
        let incomingIdentities = try incomingIdentitySet(from: payloads)
        let existingArticles = try fetchArticles(feedID: feed.id)
        let canonicalSnapshot = try canonicalArticleSnapshot(
            from: existingArticles
        )
        try articleStateIdentityRepairer.stageRepairs(
            feedID: feed.id,
            normalizedIdentities: canonicalSnapshot.duplicateIdentities,
            cancellationCheckpoint: cancellationCheckpoint,
            progressProbe: reconciliationProgressProbe
        )
        var articlesByIdentity = canonicalSnapshot.articlesByIdentity
        var projectionUpdateCount = 0
        var reconciledArticleCount = 0

        recordReconciliationProgress(
            stage: .projectionAndArchive,
            processedItemCount: 0,
            totalItemCount: articlesByIdentity.count
        )
        for (index, element) in articlesByIdentity.enumerated() {
            try checkReconciliationCancellation(
                stage: .projectionAndArchive,
                beforeItemAt: index
            )
            let (identity, article) = element
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
            recordReconciliationProgress(
                stage: .projectionAndArchive,
                processedItemCount: index + 1,
                totalItemCount: articlesByIdentity.count
            )
        }
        try checkReconciliationCancellationAfterStage(
            .projectionAndArchive
        )

        recordReconciliationProgress(
            stage: .duplicateDeletion,
            processedItemCount: 0,
            totalItemCount: canonicalSnapshot.duplicateArticles.count
        )
        for (index, duplicateArticle) in canonicalSnapshot.duplicateArticles.enumerated() {
            try checkReconciliationCancellation(
                stage: .duplicateDeletion,
                beforeItemAt: index
            )
            modelContext.delete(duplicateArticle)
            recordReconciliationProgress(
                stage: .duplicateDeletion,
                processedItemCount: index + 1,
                totalItemCount: canonicalSnapshot.duplicateArticles.count
            )
        }
        try checkReconciliationCancellationAfterStage(
            .duplicateDeletion
        )

        try cancellationCheckpoint(.beforeUpsert)
        let upsertedArticles = try applyPayloads(
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
    ) throws -> [Article] {
        var upsertedArticles: [Article] = []
        var upsertedIdentities: Set<String> = []

        recordReconciliationProgress(
            stage: .payloadApply,
            processedItemCount: 0,
            totalItemCount: payloads.count
        )
        for (index, payload) in payloads.enumerated() {
            try checkReconciliationCancellation(
                stage: .payloadApply,
                beforeItemAt: index
            )
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
            recordReconciliationProgress(
                stage: .payloadApply,
                processedItemCount: index + 1,
                totalItemCount: payloads.count
            )
        }
        try checkReconciliationCancellationAfterStage(
            .payloadApply
        )

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

    private func incomingIdentitySet(
        from payloads: [ArticleUpsertPayload]
    ) throws -> Set<String> {
        var identities: Set<String> = []
        identities.reserveCapacity(payloads.count)
        recordReconciliationProgress(
            stage: .incomingIdentityMaterialization,
            processedItemCount: 0,
            totalItemCount: payloads.count
        )

        for (index, payload) in payloads.enumerated() {
            try checkReconciliationCancellation(
                stage: .incomingIdentityMaterialization,
                beforeItemAt: index
            )
            identities.insert(normalizedArticleIdentity(payload.externalID))
            recordReconciliationProgress(
                stage: .incomingIdentityMaterialization,
                processedItemCount: index + 1,
                totalItemCount: payloads.count
            )
        }
        try checkReconciliationCancellationAfterStage(
            .incomingIdentityMaterialization
        )
        return identities
    }

    private func canonicalArticleSnapshot(
        from articles: [Article]
    ) throws -> (
        articlesByIdentity: [String: Article],
        duplicateArticles: [Article],
        duplicateIdentities: Set<String>
    ) {
        var articlesByIdentity: [String: Article] = [:]
        var duplicateArticles: [Article] = []
        var duplicateIdentities: Set<String> = []

        articlesByIdentity.reserveCapacity(articles.count)
        recordReconciliationProgress(
            stage: .snapshotCanonicalization,
            processedItemCount: 0,
            totalItemCount: articles.count
        )
        for (index, article) in articles.enumerated() {
            try checkReconciliationCancellation(
                stage: .snapshotCanonicalization,
                beforeItemAt: index
            )
            let identity = normalizedArticleIdentity(article.externalID)
            guard let existingCanonicalArticle = articlesByIdentity[identity] else {
                articlesByIdentity[identity] = article
                recordReconciliationProgress(
                    stage: .snapshotCanonicalization,
                    processedItemCount: index + 1,
                    totalItemCount: articles.count
                )
                continue
            }

            duplicateIdentities.insert(identity)
            if articleCanonicalOrder(article, existingCanonicalArticle) {
                articlesByIdentity[identity] = article
                duplicateArticles.append(existingCanonicalArticle)
            } else {
                duplicateArticles.append(article)
            }
            recordReconciliationProgress(
                stage: .snapshotCanonicalization,
                processedItemCount: index + 1,
                totalItemCount: articles.count
            )
        }
        try checkReconciliationCancellationAfterStage(
            .snapshotCanonicalization
        )

        return (articlesByIdentity, duplicateArticles, duplicateIdentities)
    }

    private func checkReconciliationCancellation(
        stage: ArticleFeedSnapshotReconciliationStage,
        beforeItemAt index: Int
    ) throws {
        guard index.isMultiple(
            of: ArticleFeedSnapshotReconciliationPolicy.cancellationCheckpointInterval
        ) else {
            return
        }
        try cancellationCheckpoint(.during(stage))
    }

    private func checkReconciliationCancellationAfterStage(
        _ stage: ArticleFeedSnapshotReconciliationStage
    ) throws {
        try cancellationCheckpoint(.during(stage))
    }

    private func recordReconciliationProgress(
        stage: ArticleFeedSnapshotReconciliationStage,
        processedItemCount: Int,
        totalItemCount: Int
    ) {
        reconciliationProgressProbe?(
            ArticleFeedSnapshotReconciliationProgress(
                stage: stage,
                processedItemCount: processedItemCount,
                totalItemCount: totalItemCount
            )
        )
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
