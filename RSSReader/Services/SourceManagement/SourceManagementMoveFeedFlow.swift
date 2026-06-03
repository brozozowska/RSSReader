import Foundation

@MainActor
struct SourceManagementMoveFeedFlow {
    let logger: Logging
    let feedRepository: any FeedRepository
    let articleRepository: any ArticleRepository
    let normalizationPolicy: SourceManagementNormalizationPolicy
    let summaryMapper: SourceManagementSummaryMapper

    func moveFeed(_ command: SourceManagementMoveFeedCommand) throws -> SourceManagementFeedSummary {
        guard try feedRepository.fetchMetadata(for: command.feedID) != nil else {
            logger.error("Skipped feed move because feed was not found: \(command.feedID.uuidString)")
            throw SourceManagementServiceError.feedNotFound(command.feedID)
        }

        let folder = try normalizationPolicy.resolveFolder(for: command.folderPlacement)
        let update = FeedFolderAssignmentUpdate(
            folder: folder,
            updatedAt: command.updatedAt
        )
        let feed = try feedRepository.updateFolderAssignment(
            for: command.feedID,
            with: update
        )
        if let feed {
            _ = try articleRepository.refreshFeedProjection(for: feed, saveAfterOperation: false)
            try feedRepository.save()
        }

        return summaryMapper.feedSummary(
            from: try normalizationPolicy.requireFeedSummarySource(
                feed,
                feedID: command.feedID,
                operation: "move"
            )
        )
    }
}
