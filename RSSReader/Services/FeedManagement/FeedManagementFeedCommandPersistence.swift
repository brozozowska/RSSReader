import Foundation

@MainActor
struct FeedManagementFeedCommandPersistence {
    let logger: Logging
    let feedRepository: any FeedRepository
    let articleRepository: any ArticleRepository
    let normalizationPolicy: FeedManagementNormalizationPolicy
    let summaryMapper: FeedManagementSummaryMapper

    func createFeed(_ command: FeedManagementCreateFeedCommand) throws -> FeedManagementFeedSummary {
        if try normalizationPolicy.existingFeed(
            resolvedFeedURL: command.preview.resolvedFeedURL,
            requestedURL: command.preview.requestedURL
        ) != nil {
            logger.error("Skipped feed creation because feed already exists: \(command.preview.resolvedFeedURL)")
            throw FeedManagementServiceError.duplicateFeed(command.preview.resolvedFeedURL)
        }

        let folder = try normalizationPolicy.resolveFolder(for: command.folderPlacement)
        let displayTitle = normalizationPolicy.normalizedDisplayTitle(command.displayTitleOverride) ?? command.preview.title
        try normalizationPolicy.ensureUniqueFeedDisplayTitle(displayTitle)
        let feed = try feedRepository.insert(
            Feed(
                url: command.preview.resolvedFeedURL,
                siteURL: command.preview.siteURL,
                title: command.preview.title,
                displayTitleOverride: normalizationPolicy.normalizedDisplayTitle(command.displayTitleOverride),
                subtitle: command.preview.subtitle,
                iconURL: nil,
                language: command.preview.language,
                kind: command.preview.kind,
                folder: folder,
                createdAt: command.createdAt,
                updatedAt: command.createdAt
            )
        )

        return summaryMapper.feedSummary(from: feed)
    }

    func updateFeed(_ command: FeedManagementUpdateFeedCommand) throws -> FeedManagementFeedSummary {
        guard let currentFeed = try feedRepository.fetchFeed(id: command.feedID) else {
            logger.error("Skipped feed update because feed was not found: \(command.feedID.uuidString)")
            throw FeedManagementServiceError.feedNotFound(command.feedID)
        }

        let folder = try normalizationPolicy.resolveFolder(for: command.folderPlacement)
        let displayTitleOverride = normalizationPolicy.normalizedDisplayTitle(command.displayTitleOverride)
        let metadataTitle = currentFeed.title
        try normalizationPolicy.ensureUniqueFeedDisplayTitle(displayTitleOverride ?? metadataTitle, excluding: command.feedID)

        do {
            let updatedFeed = try feedRepository.updateDetails(
                for: command.feedID,
                with: FeedDetailsUpdate(
                    displayTitleOverride: displayTitleOverride,
                    clearsDisplayTitleOverride: displayTitleOverride == nil,
                    updatedAt: command.updatedAt
                ),
                saveAfterOperation: false
            )
            let finalFeed = try feedRepository.updateFolderAssignment(
                for: command.feedID,
                with: FeedFolderAssignmentUpdate(
                    folder: folder,
                    updatedAt: command.updatedAt
                ),
                saveAfterOperation: false
            ) ?? updatedFeed
            if let finalFeed {
                _ = try articleRepository.refreshFeedProjection(for: finalFeed, saveAfterOperation: false)
            }
            try feedRepository.save()
            return summaryMapper.feedSummary(
                from: try normalizationPolicy.requireFeedSummary(
                    finalFeed,
                    feedID: command.feedID,
                    operation: "update"
                )
            )
        } catch {
            feedRepository.rollback()
            throw error
        }
    }

    func deleteFeed(id feedID: UUID) throws {
        let didDelete = try feedRepository.delete(feedID: feedID)
        guard didDelete else {
            logger.error("Skipped feed deletion because feed was not found: \(feedID.uuidString)")
            throw FeedManagementServiceError.feedNotFound(feedID)
        }
    }
}
