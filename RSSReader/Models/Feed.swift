import Foundation
import SwiftData

@Model
final class Feed {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var url: String
    var siteURL: String?
    var title: String
    var subtitle: String?
    var iconURL: String?
    var language: String?
    var kind: FeedKind
    var isActive: Bool
    var folder: Folder?
    @Relationship(deleteRule: .cascade, inverse: \Article.feed)
    var articles: [Article] = []
    var lastFetchedAt: Date?
    var lastSuccessfulFetchAt: Date?
    var lastETag: String?
    var lastModifiedHeader: String?
    var lastSyncError: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        url: String,
        siteURL: String? = nil,
        title: String,
        subtitle: String? = nil,
        iconURL: String? = nil,
        language: String? = nil,
        kind: FeedKind = .unknown,
        isActive: Bool = true,
        folder: Folder? = nil,
        lastFetchedAt: Date? = nil,
        lastSuccessfulFetchAt: Date? = nil,
        lastETag: String? = nil,
        lastModifiedHeader: String? = nil,
        lastSyncError: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.url = url
        self.siteURL = siteURL
        self.title = title
        self.subtitle = subtitle
        self.iconURL = iconURL
        self.language = language
        self.kind = kind
        self.isActive = isActive
        self.folder = folder
        self.lastFetchedAt = lastFetchedAt
        self.lastSuccessfulFetchAt = lastSuccessfulFetchAt
        self.lastETag = lastETag
        self.lastModifiedHeader = lastModifiedHeader
        self.lastSyncError = lastSyncError
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
