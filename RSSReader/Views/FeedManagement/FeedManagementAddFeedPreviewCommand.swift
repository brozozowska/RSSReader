import Foundation

struct FeedManagementAddFeedPreviewCommand: Equatable, Sendable {
    let requestID: UUID
    let urlString: String
}
