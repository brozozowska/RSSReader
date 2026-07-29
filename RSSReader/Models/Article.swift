import Foundation
import SwiftData

@Model
final class Article {
    #Index<Article>(
        [\.querySortDate],
        [\.feedID, \.querySortDate],
        [\.feedFolderName, \.querySortDate],
        [\.feedID, \.externalID]
    )

    var id: UUID = UUID()
    var feedID: UUID = UUID()
    var feedTitle: String = ""
    var feedSiteURL: String?
    var feedFolderName: String?
    var externalID: String = ""
    var guid: String?
    var url: String = ""
    var canonicalURL: String?
    var title: String = ""
    var summary: String?
    var contentHTML: String?
    var contentText: String?
    var searchableText: String = ""
    var searchableTextVersion: Int = 0
    var searchableTextSourceRevision: Int = 0
    var searchableTextMaterializedSourceRevision: Int = -1
    var author: String?
    var publishedAt: Date?
    var querySortDate: Date = Date.distantPast
    var updatedAtSource: Date?
    var imageURL: String?
    var archivedAt: Date?
    var fetchedAt: Date = Date.now
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(
        id: UUID = UUID(),
        feedID: UUID,
        feedTitle: String,
        feedSiteURL: String? = nil,
        feedFolderName: String? = nil,
        externalID: String,
        guid: String? = nil,
        url: String,
        canonicalURL: String? = nil,
        title: String,
        summary: String? = nil,
        contentHTML: String? = nil,
        contentText: String? = nil,
        searchableText: String? = nil,
        author: String? = nil,
        publishedAt: Date? = nil,
        updatedAtSource: Date? = nil,
        imageURL: String? = nil,
        archivedAt: Date? = nil,
        fetchedAt: Date = .now,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.feedID = feedID
        self.feedTitle = feedTitle
        self.feedSiteURL = feedSiteURL
        self.feedFolderName = feedFolderName
        self.externalID = externalID
        self.guid = guid
        self.url = url
        self.canonicalURL = canonicalURL
        self.title = title
        self.summary = summary
        self.contentHTML = contentHTML
        self.contentText = contentText
        self.searchableText = searchableText ?? ArticleSearchableTextPolicy.materialize(
            title: title,
            summary: summary,
            contentHTML: contentHTML,
            contentText: contentText,
            author: author
        )
        self.searchableTextVersion = ArticleSearchableTextPolicy.currentVersion
        self.searchableTextSourceRevision = 1
        self.searchableTextMaterializedSourceRevision = 1
        self.author = author
        self.publishedAt = publishedAt
        self.querySortDate = publishedAt ?? fetchedAt
        self.updatedAtSource = updatedAtSource
        self.imageURL = imageURL
        self.archivedAt = archivedAt
        self.fetchedAt = fetchedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    @discardableResult
    func rebuildSearchableTextIfNeeded() -> Bool {
        guard searchableTextVersion != ArticleSearchableTextPolicy.currentVersion
                || searchableTextMaterializedSourceRevision != searchableTextSourceRevision else {
            return false
        }

        searchableText = ArticleSearchableTextPolicy.materialize(
            title: title,
            summary: summary,
            contentHTML: contentHTML,
            contentText: contentText,
            author: author
        )
        searchableTextVersion = ArticleSearchableTextPolicy.currentVersion
        searchableTextMaterializedSourceRevision = searchableTextSourceRevision
        return true
    }

    func applyPreparedSearchableText(
        _ value: String,
        sourceDidChange: Bool
    ) {
        if sourceDidChange {
            searchableTextSourceRevision += 1
        }
        searchableText = value
        searchableTextVersion = ArticleSearchableTextPolicy.currentVersion
        searchableTextMaterializedSourceRevision = searchableTextSourceRevision
    }
}
