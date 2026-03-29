import Foundation

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
