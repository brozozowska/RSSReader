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

    init(
        id: UUID,
        feedID: UUID,
        feedTitle: String,
        feedSiteURL: String?,
        articleExternalID: String,
        title: String,
        summary: String?,
        contentHTML: String?,
        contentText: String?,
        author: String?,
        publishedAt: Date?,
        updatedAtSource: Date?,
        articleURL: String,
        canonicalURL: String?,
        imageURL: String?,
        isRead: Bool,
        isStarred: Bool,
        isHidden: Bool
    ) {
        self.id = id
        self.feedID = feedID
        self.feedTitle = feedTitle
        self.feedSiteURL = feedSiteURL
        self.articleExternalID = articleExternalID
        self.title = title
        self.summary = summary
        self.contentHTML = contentHTML
        self.contentText = contentText
        self.author = author
        self.publishedAt = publishedAt
        self.updatedAtSource = updatedAtSource
        self.articleURL = articleURL
        self.canonicalURL = canonicalURL
        self.imageURL = imageURL
        self.isRead = isRead
        self.isStarred = isStarred
        self.isHidden = isHidden
    }

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

    init(article: Article, state: ArticleUserStateSnapshot?) {
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
