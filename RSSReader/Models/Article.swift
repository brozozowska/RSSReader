import Foundation
import SwiftData

@Model
final class Article {
    #Index<Article>([\.publishedAt])

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
    var author: String?
    var publishedAt: Date?
    var updatedAtSource: Date?
    var imageURL: String?
    var isDeletedAtSource: Bool = false
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
        author: String? = nil,
        publishedAt: Date? = nil,
        updatedAtSource: Date? = nil,
        imageURL: String? = nil,
        isDeletedAtSource: Bool = false,
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
        self.author = author
        self.publishedAt = publishedAt
        self.updatedAtSource = updatedAtSource
        self.imageURL = imageURL
        self.isDeletedAtSource = isDeletedAtSource
        self.archivedAt = archivedAt
        self.fetchedAt = fetchedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
