import Foundation

@MainActor
protocol ArticleQueryService {
    func fetchArticleListItems(feedID: UUID, sortMode: ArticleSortMode) throws -> [ArticleListItemDTO]
    func fetchArticleListItems(feedID: UUID, sortMode: ArticleSortMode, filter: ArticleListFilter) throws -> [ArticleListItemDTO]
    func fetchInboxListItems(sortMode: ArticleSortMode) throws -> [ArticleListItemDTO]
    func fetchInboxListItems(sortMode: ArticleSortMode, filter: ArticleListFilter) throws -> [ArticleListItemDTO]
    func fetchReaderArticle(id: UUID) throws -> ReaderArticleDTO?
}

@MainActor
final class DefaultArticleQueryService: ArticleQueryService {
    private let articleRepository: any ArticleRepository
    private let articleStateRepository: any ArticleStateRepository

    init(
        articleRepository: any ArticleRepository,
        articleStateRepository: any ArticleStateRepository
    ) {
        self.articleRepository = articleRepository
        self.articleStateRepository = articleStateRepository
    }

    func fetchArticleListItems(feedID: UUID, sortMode: ArticleSortMode) throws -> [ArticleListItemDTO] {
        try fetchArticleListItems(feedID: feedID, sortMode: sortMode, filter: .all)
    }

    func fetchArticleListItems(
        feedID: UUID,
        sortMode: ArticleSortMode,
        filter: ArticleListFilter
    ) throws -> [ArticleListItemDTO] {
        let articles = try articleRepository.fetchArticles(feedID: feedID, sortMode: sortMode)
        let stateByCompositeKey = try fetchStateByCompositeKey(for: articles)

        return articles.compactMap { article in
            let state = stateByCompositeKey[articleCompositeKey(feedID: article.feedID, articleExternalID: article.externalID)]
            let item = ArticleListItemDTO(article: article, state: state)
            return matches(filter: filter, item: item) ? item : nil
        }
    }

    func fetchInboxListItems(sortMode: ArticleSortMode) throws -> [ArticleListItemDTO] {
        try fetchInboxListItems(sortMode: sortMode, filter: .all)
    }

    func fetchInboxListItems(sortMode: ArticleSortMode, filter: ArticleListFilter) throws -> [ArticleListItemDTO] {
        let articles = try articleRepository.fetchInbox(sortMode: sortMode)
        let stateByCompositeKey = try fetchStateByCompositeKey(for: articles)

        return articles.compactMap { article in
            let state = stateByCompositeKey[articleCompositeKey(feedID: article.feedID, articleExternalID: article.externalID)]
            let item = ArticleListItemDTO(article: article, state: state)
            return matches(filter: filter, item: item) ? item : nil
        }
    }

    func fetchReaderArticle(id: UUID) throws -> ReaderArticleDTO? {
        guard let article = try articleRepository.fetchArticle(id: id) else { return nil }

        let stateByCompositeKey = try fetchStateByCompositeKey(for: [article])
        let state = stateByCompositeKey[articleCompositeKey(feedID: article.feedID, articleExternalID: article.externalID)]
        return ReaderArticleDTO(article: article, state: state)
    }

    private func fetchStateByCompositeKey(for articles: [Article]) throws -> [String: ArticleUserStateSnapshot] {
        guard articles.isEmpty == false else { return [:] }

        return try articleStateRepository.fetchStateSnapshots(for: articles)
    }

    private func articleCompositeKey(feedID: UUID, articleExternalID: String) -> String {
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
}
