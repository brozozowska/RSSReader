import Foundation
@testable import RSSReader

func makeArticleListItemDTO(
    id: UUID = UUID(),
    feedID: UUID = UUID(),
    feedTitle: String = "Feed",
    articleExternalID: String = "article",
    title: String = "Article",
    summary: String? = "Summary",
    author: String? = nil,
    publishedAt: Date? = nil,
    archivedAt: Date? = nil,
    isRead: Bool = false,
    isStarred: Bool = false,
    isHidden: Bool = false
) -> ArticleListItemDTO {
    ArticleListItemDTO(
        id: id,
        feedID: feedID,
        feedTitle: feedTitle,
        articleExternalID: articleExternalID,
        title: title,
        summary: summary,
        author: author,
        publishedAt: publishedAt,
        fetchedAt: .now,
        archivedAt: archivedAt,
        isRead: isRead,
        isStarred: isStarred,
        isHidden: isHidden
    )
}

func makeArticleSearchCandidateDTO(
    id: UUID = UUID(),
    feedID: UUID = UUID(),
    feedTitle: String = "Feed",
    articleExternalID: String = "article",
    title: String = "Article",
    summary: String? = "Summary",
    contentHTML: String? = nil,
    contentText: String? = nil,
    searchableText: String? = nil,
    author: String? = nil,
    publishedAt: Date? = nil,
    archivedAt: Date? = nil,
    isRead: Bool = false,
    isStarred: Bool = false,
    isHidden: Bool = false
) -> ArticleSearchCandidateDTO {
    let listItem = makeArticleListItemDTO(
        id: id,
        feedID: feedID,
        feedTitle: feedTitle,
        articleExternalID: articleExternalID,
        title: title,
        summary: summary,
        author: author,
        publishedAt: publishedAt,
        archivedAt: archivedAt,
        isRead: isRead,
        isStarred: isStarred,
        isHidden: isHidden
    )
    return ArticleSearchCandidateDTO(
        listItem: listItem,
        searchableText: searchableText ?? ArticleSearchableTextPolicy.materialize(
            title: title,
            summary: summary,
            contentHTML: contentHTML,
            contentText: contentText,
            author: author
        )
    )
}

@MainActor
func makeReaderArticleDTO(
    id: UUID = UUID(),
    feedID: UUID = UUID(),
    feedTitle: String = "Feed",
    feedSiteURL: String? = "https://example.com",
    articleExternalID: String = "article",
    title: String = "Article",
    summary: String? = "Summary",
    contentHTML: String? = nil,
    contentText: String? = nil,
    author: String? = "Author",
    publishedAt: Date? = nil,
    articleURL: String = "https://example.com/articles/1",
    canonicalURL: String? = "https://example.com/articles/1/canonical",
    imageURL: String? = nil,
    isRead: Bool = false,
    isStarred: Bool = false,
    isHidden: Bool = false
) -> ReaderArticleDTO {
    ReaderArticleDTO(
        id: id,
        feedID: feedID,
        feedTitle: feedTitle,
        feedSiteURL: feedSiteURL,
        articleExternalID: articleExternalID,
        title: title,
        summary: summary,
        contentHTML: contentHTML,
        contentText: contentText,
        author: author,
        publishedAt: publishedAt,
        updatedAtSource: nil,
        articleURL: articleURL,
        canonicalURL: canonicalURL,
        imageURL: imageURL,
        isRead: isRead,
        isStarred: isStarred,
        isHidden: isHidden
    )
}

func makeValidRSSFeedXML(
    channelTitle: String,
    channelLink: String,
    channelImageURL: String? = nil,
    language: String,
    itemTitle: String,
    itemLink: String,
    itemGUID: String,
    itemDescription: String,
    pubDate: String
) -> String {
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0">
      <channel>
        <title>\(channelTitle)</title>
        <link>\(channelLink)</link>
        <description>Integration test feed</description>
        \(channelImageXML(channelImageURL, title: channelTitle, link: channelLink))
        <language>\(language)</language>
        <item>
          <title>\(itemTitle)</title>
          <link>\(itemLink)</link>
          <guid isPermaLink="false">\(itemGUID)</guid>
          <description>\(itemDescription)</description>
          <pubDate>\(pubDate)</pubDate>
        </item>
      </channel>
    </rss>
    """
}

private func channelImageXML(_ imageURL: String?, title: String, link: String) -> String {
    guard let imageURL else { return "" }

    return """
        <image>
          <url>\(imageURL)</url>
          <title>\(title)</title>
          <link>\(link)</link>
        </image>
    """
}
