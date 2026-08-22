import Foundation
import SwiftData

nonisolated enum ArticleStateIdentity {
    static func lookupKey(feedID: UUID, articleExternalID: String) -> String {
        let normalizedExternalID = articleExternalID.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(feedID.uuidString)|\(normalizedExternalID)"
    }
}

@Model
final class ArticleState {
    #Index<ArticleState>(
        [\.updatedAt],
        [\.feedID, \.articleExternalID, \.updatedAt]
    )

    var id: UUID = UUID()
    var articleExternalID: String = ""
    var feedID: UUID = UUID()
    var isRead: Bool = false
    var readAt: Date?
    var isStarred: Bool = false
    var starredAt: Date?
    var isHidden: Bool = false
    var hiddenAt: Date?
    var lastInteractionAt: Date?
    var updatedAt: Date = Date.now

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
