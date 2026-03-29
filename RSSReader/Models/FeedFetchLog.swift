import Foundation
import SwiftData

struct FeedFetchLogEntry: Sendable {
    let feedID: UUID
    let status: String
    let httpCode: Int?
    let message: String?
    let createdAt: Date

    init(
        feedID: UUID,
        status: String,
        httpCode: Int? = nil,
        message: String? = nil,
        createdAt: Date = .now
    ) {
        self.feedID = feedID
        self.status = status
        self.httpCode = httpCode
        self.message = message
        self.createdAt = createdAt
    }
}

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

    convenience init(entry: FeedFetchLogEntry) {
        self.init(
            feedID: entry.feedID,
            status: entry.status,
            httpCode: entry.httpCode,
            message: entry.message,
            createdAt: entry.createdAt
        )
    }
}
