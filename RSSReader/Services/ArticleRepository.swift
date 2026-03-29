import Foundation
import SwiftData

enum ArticleListFilter: String, Sendable, CaseIterable {
    case all
    case unread
    case starred
    case hidden
}

struct ArticleListItemDTO: Sendable, Identifiable {
    let id: UUID
    let feedID: UUID
    let feedTitle: String
    let articleExternalID: String
    let title: String
    let summary: String?
    let author: String?
    let publishedAt: Date?
    let fetchedAt: Date
    let isRead: Bool
    let isStarred: Bool
    let isHidden: Bool

    init(article: Article, state: ArticleState?) {
        self.id = article.id
        self.feedID = article.feedID
        self.feedTitle = article.feed.title
        self.articleExternalID = article.externalID
        self.title = article.title
        self.summary = article.summary
        self.author = article.author
        self.publishedAt = article.publishedAt
        self.fetchedAt = article.fetchedAt
        self.isRead = state?.isRead ?? false
        self.isStarred = state?.isStarred ?? false
        self.isHidden = state?.isHidden ?? false
    }
}

struct ReaderArticleDTO: Sendable, Identifiable {
    let id: UUID
    let feedID: UUID
    let feedTitle: String
    let feedSiteURL: String?
    let articleExternalID: String
    let title: String
    let summary: String?
    let contentHTML: String?
    let contentText: String?
    let author: String?
    let publishedAt: Date?
    let updatedAtSource: Date?
    let articleURL: String
    let canonicalURL: String?
    let imageURL: String?
    let isRead: Bool
    let isStarred: Bool
    let isHidden: Bool

    init(article: Article, state: ArticleState?) {
        self.id = article.id
        self.feedID = article.feedID
        self.feedTitle = article.feed.title
        self.feedSiteURL = article.feed.siteURL
        self.articleExternalID = article.externalID
        self.title = article.title
        self.summary = article.summary
        self.contentHTML = article.contentHTML
        self.contentText = article.contentText
        self.author = article.author
        self.publishedAt = article.publishedAt
        self.updatedAtSource = article.updatedAtSource
        self.articleURL = article.url
        self.canonicalURL = article.canonicalURL
        self.imageURL = article.imageURL
        self.isRead = state?.isRead ?? false
        self.isStarred = state?.isStarred ?? false
        self.isHidden = state?.isHidden ?? false
    }
}

struct ArticleUpsertPayload: Sendable {
    let externalID: String
    let guid: String?
    let url: String
    let canonicalURL: String?
    let title: String
    let summary: String?
    let contentHTML: String?
    let contentText: String?
    let author: String?
    let publishedAt: Date?
    let updatedAtSource: Date?
    let imageURL: String?
    let isDeletedAtSource: Bool
    let fetchedAt: Date

    init?(
        entry: ParsedFeedEntryDTO,
        fetchedAt: Date = .now,
        isDeletedAtSource: Bool = false
    ) {
        guard
            let externalID = entry.externalID,
            let url = entry.url,
            let title = entry.title ?? entry.summary
        else {
            return nil
        }

        self.externalID = externalID
        self.guid = entry.guid
        self.url = url
        self.canonicalURL = entry.canonicalURL
        self.title = title
        self.summary = entry.summary
        self.contentHTML = entry.contentHTML
        self.contentText = entry.contentText
        self.author = entry.author
        self.publishedAt = FeedNormalizationService.parsePublishedAt(for: entry)
        self.updatedAtSource = FeedNormalizationService.parseUpdatedAt(for: entry)
        self.imageURL = entry.imageURL
        self.isDeletedAtSource = isDeletedAtSource
        self.fetchedAt = fetchedAt
    }
}

@MainActor
protocol ArticleRepository {
    func fetchArticle(id: UUID) throws -> Article?
    func fetchArticle(feedID: UUID, externalID: String) throws -> Article?
    func fetchArticles(feedID: UUID, sortMode: ArticleSortMode) throws -> [Article]
    func fetchInbox(sortMode: ArticleSortMode) throws -> [Article]
    func fetchArticleListItems(feedID: UUID, sortMode: ArticleSortMode) throws -> [ArticleListItemDTO]
    func fetchArticleListItems(feedID: UUID, sortMode: ArticleSortMode, filter: ArticleListFilter) throws -> [ArticleListItemDTO]
    func fetchInboxListItems(sortMode: ArticleSortMode) throws -> [ArticleListItemDTO]
    func fetchInboxListItems(sortMode: ArticleSortMode, filter: ArticleListFilter) throws -> [ArticleListItemDTO]
    func fetchReaderArticle(id: UUID) throws -> ReaderArticleDTO?

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
final class SwiftDataArticleRepository: ArticleRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchArticle(id: UUID) throws -> Article? {
        var descriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { article in
                article.id == id
            }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func fetchArticle(feedID: UUID, externalID: String) throws -> Article? {
        var descriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { article in
                article.feed.id == feedID && article.externalID == externalID
            }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
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

    func fetchArticleListItems(feedID: UUID, sortMode: ArticleSortMode) throws -> [ArticleListItemDTO] {
        try fetchArticleListItems(feedID: feedID, sortMode: sortMode, filter: .all)
    }

    func fetchArticleListItems(feedID: UUID, sortMode: ArticleSortMode, filter: ArticleListFilter) throws -> [ArticleListItemDTO] {
        let articles = try fetchArticles(feedID: feedID, sortMode: sortMode)
        let stateByCompositeKey = try fetchStateByCompositeKey(for: articles)

        return articles.compactMap { article in
            let state = stateByCompositeKey[compositeKey(feedID: article.feedID, articleExternalID: article.externalID)]
            let item = ArticleListItemDTO(article: article, state: state)
            return matches(filter: filter, item: item) ? item : nil
        }
    }

    func fetchInboxListItems(sortMode: ArticleSortMode) throws -> [ArticleListItemDTO] {
        try fetchInboxListItems(sortMode: sortMode, filter: .all)
    }

    func fetchInboxListItems(sortMode: ArticleSortMode, filter: ArticleListFilter) throws -> [ArticleListItemDTO] {
        let articles = try fetchInbox(sortMode: sortMode)
        let stateByCompositeKey = try fetchStateByCompositeKey(for: articles)

        return articles.compactMap { article in
            let state = stateByCompositeKey[compositeKey(feedID: article.feedID, articleExternalID: article.externalID)]
            let item = ArticleListItemDTO(article: article, state: state)
            return matches(filter: filter, item: item) ? item : nil
        }
    }

    func fetchReaderArticle(id: UUID) throws -> ReaderArticleDTO? {
        guard let article = try fetchArticle(id: id) else { return nil }

        let stateByCompositeKey = try fetchStateByCompositeKey(for: [article])
        let state = stateByCompositeKey[compositeKey(feedID: article.feedID, articleExternalID: article.externalID)]
        return ReaderArticleDTO(article: article, state: state)
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

    private func fetchStateByCompositeKey(for articles: [Article]) throws -> [String: ArticleState] {
        guard articles.isEmpty == false else { return [:] }

        let descriptor = FetchDescriptor<ArticleState>()
        let states = try modelContext.fetch(descriptor)
        let relevantKeys = Set(articles.map { compositeKey(feedID: $0.feedID, articleExternalID: $0.externalID) })

        return states.reduce(into: [String: ArticleState]()) { partialResult, state in
            let key = compositeKey(feedID: state.feedID, articleExternalID: state.articleExternalID)
            guard relevantKeys.contains(key) else { return }
            partialResult[key] = state
        }
    }

    private func compositeKey(feedID: UUID, articleExternalID: String) -> String {
        "\(feedID.uuidString)|\(articleExternalID)"
    }

    private func matches(filter: ArticleListFilter, item: ArticleListItemDTO) -> Bool {
        switch filter {
        case .all:
            item.isHidden == false
        case .unread:
            item.isHidden == false && item.isRead == false
        case .starred:
            item.isHidden == false && item.isStarred
        case .hidden:
            item.isHidden
        }
    }

    private func saveIfNeeded(force: Bool = false) throws {
        guard force || modelContext.hasChanges else { return }
        try modelContext.save()
    }
}
