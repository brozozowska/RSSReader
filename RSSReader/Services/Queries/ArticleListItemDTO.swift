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
