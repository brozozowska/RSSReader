import Foundation
import SwiftData

@Model
final class ArticleState {
    #Unique<ArticleState>([\.feedID, \.articleExternalID])

    @Attribute(.unique) var id: UUID
    var articleExternalID: String
    var feedID: UUID
    var isRead: Bool
    var readAt: Date?
    var isStarred: Bool
    var starredAt: Date?
    var isHidden: Bool
    var hiddenAt: Date?
    var lastInteractionAt: Date?
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        articleExternalID: String,
        feedID: UUID,
        isRead: Bool = false,
        readAt: Date? = nil,
        isStarred: Bool = false,
        starredAt: Date? = nil,
        isHidden: Bool = false,
        hiddenAt: Date? = nil,
        lastInteractionAt: Date? = nil,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.articleExternalID = articleExternalID
        self.feedID = feedID
        self.isRead = isRead
        self.readAt = readAt
        self.isStarred = isStarred
        self.starredAt = starredAt
        self.isHidden = isHidden
        self.hiddenAt = hiddenAt
        self.lastInteractionAt = lastInteractionAt
        self.updatedAt = updatedAt
    }
}
