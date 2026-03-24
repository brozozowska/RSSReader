import Foundation
import SwiftData

@Model
final class Article {
    #Unique<Article>([\.feed, \.externalID])
    #Index<Article>([\.publishedAt])

    @Attribute(.unique) var id: UUID
    var feed: Feed
    var externalID: String
    var guid: String?
    var url: String
    var canonicalURL: String?
    var title: String
    var summary: String?
    var contentHTML: String?
    var contentText: String?
    var author: String?
    var publishedAt: Date?
    var updatedAtSource: Date?
    var imageURL: String?
    var isDeletedAtSource: Bool
    var fetchedAt: Date
    var createdAt: Date
    var updatedAt: Date

    var feedID: UUID {
        feed.id
    }

    init(
        id: UUID = UUID(),
        feed: Feed,
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
        fetchedAt: Date = .now,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.feed = feed
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
        self.fetchedAt = fetchedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
