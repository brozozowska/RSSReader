import Foundation

struct SourceManagementAddFeedPreviewCommand: Equatable, Sendable {
    let requestID: UUID
    let urlString: String
}
