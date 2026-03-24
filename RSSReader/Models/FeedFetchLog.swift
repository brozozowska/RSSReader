import Foundation
import SwiftData

@Model
final class FeedFetchLog {
    @Attribute(.unique) var id: UUID
    var feedID: UUID
    var status: String
    var httpCode: Int?
    var message: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        feedID: UUID,
        status: String,
        httpCode: Int? = nil,
        message: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.feedID = feedID
        self.status = status
        self.httpCode = httpCode
        self.message = message
        self.createdAt = createdAt
    }
}
