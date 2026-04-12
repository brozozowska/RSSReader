import Foundation

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

    init(
        id: UUID,
        feedID: UUID,
        feedTitle: String,
        articleExternalID: String,
        title: String,
        summary: String?,
        author: String?,
        publishedAt: Date?,
        fetchedAt: Date,
        isRead: Bool,
        isStarred: Bool,
        isHidden: Bool
    ) {
        self.id = id
        self.feedID = feedID
        self.feedTitle = feedTitle
        self.articleExternalID = articleExternalID
        self.title = title
        self.summary = summary
        self.author = author
        self.publishedAt = publishedAt
        self.fetchedAt = fetchedAt
        self.isRead = isRead
        self.isStarred = isStarred
        self.isHidden = isHidden
    }

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

    init(article: Article, state: ArticleUserStateSnapshot?) {
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
