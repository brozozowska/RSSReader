import Foundation
import SwiftData

@MainActor
protocol ArticleRepository {
    func fetchArticle(id: UUID) throws -> Article?
    func fetchArticle(feedID: UUID, externalID: String) throws -> Article?
    func fetchArticles(feedID: UUID, sortMode: ArticleSortMode) throws -> [Article]
    func fetchInbox(sortMode: ArticleSortMode) throws -> [Article]

    @discardableResult
    func upsert(_ entry: ParsedFeedEntryDTO, into feed: Feed, fetchedAt: Date) throws -> Article?

    @discardableResult
    func upsert(_ entries: [ParsedFeedEntryDTO], into feed: Feed, fetchedAt: Date) throws -> [Article]

    @discardableResult
    func upsert(_ payload: ArticleUpsertPayload, into feed: Feed) throws -> Article

    @discardableResult
    func upsert(_ payloads: [ArticleUpsertPayload], into feed: Feed) throws -> [Article]

    func save() throws
    func delete(_ article: Article) throws
}

@MainActor
final class SwiftDataArticleRepository: ArticleRepository, SwiftDataRepositoryContext {
    let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
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
                article.feed.id == feedID && article.externalID == externalID
            }
        )
        return try fetchFirst(descriptor)
    }

    func fetchArticles(feedID: UUID, sortMode: ArticleSortMode) throws -> [Article] {
        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { article in
                article.feed.id == feedID && article.isDeletedAtSource == false
            },
            sortBy: sortDescriptors(for: sortMode)
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchInbox(sortMode: ArticleSortMode) throws -> [Article] {
        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { article in
                article.isDeletedAtSource == false
            },
            sortBy: sortDescriptors(for: sortMode)
        )
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
    func upsert(_ entries: [ParsedFeedEntryDTO], into feed: Feed, fetchedAt: Date = .now) throws -> [Article] {
        let payloads = entries.compactMap { ArticleUpsertPayload(entry: $0, fetchedAt: fetchedAt) }
        return try upsert(payloads, into: feed)
    }

    @discardableResult
    func upsert(_ payload: ArticleUpsertPayload, into feed: Feed) throws -> Article {
        try upsert(payload, into: feed, saveAfterOperation: true)
    }

    @discardableResult
    func upsert(_ payloads: [ArticleUpsertPayload], into feed: Feed) throws -> [Article] {
        let articles = try payloads.map { payload in
            try upsert(payload, into: feed, saveAfterOperation: false)
        }
        try saveIfNeeded()
        return articles
    }

    func save() throws {
        try saveIfNeeded(force: true)
    }

    func delete(_ article: Article) throws {
        modelContext.delete(article)
        try saveIfNeeded()
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
        article.isDeletedAtSource = payload.isDeletedAtSource
        article.fetchedAt = payload.fetchedAt
        article.updatedAt = .now
    }

    private func upsert(
        _ payload: ArticleUpsertPayload,
        into feed: Feed,
        saveAfterOperation: Bool
    ) throws -> Article {
        if let existingArticle = try fetchArticle(feedID: feed.id, externalID: payload.externalID) {
            apply(payload, to: existingArticle)
            if saveAfterOperation {
                try saveIfNeeded()
            }
            return existingArticle
        }

        let article = Article(
            feed: feed,
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
            isDeletedAtSource: payload.isDeletedAtSource,
            fetchedAt: payload.fetchedAt
        )

        modelContext.insert(article)
        if saveAfterOperation {
            try saveIfNeeded()
        }
        return article
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
        case .fetchedAtDescending:
            [
                SortDescriptor(\Article.fetchedAt, order: .reverse),
                SortDescriptor(\Article.createdAt, order: .reverse)
            ]
        }
    }
}
