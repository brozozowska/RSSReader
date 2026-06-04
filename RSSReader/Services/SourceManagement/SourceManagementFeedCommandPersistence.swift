import Foundation

@MainActor
struct SourceManagementFeedCommandPersistence {
    let logger: Logging
    let feedRepository: any FeedRepository
    let articleRepository: any ArticleRepository
    let normalizationPolicy: SourceManagementNormalizationPolicy
    let summaryMapper: SourceManagementSummaryMapper

    func createFeed(_ command: SourceManagementCreateFeedCommand) throws -> SourceManagementFeedSummary {
        if try normalizationPolicy.existingFeed(
            resolvedFeedURL: command.preview.resolvedFeedURL,
            requestedURL: command.preview.requestedURL
        ) != nil {
            logger.error("Skipped feed creation because feed already exists: \(command.preview.resolvedFeedURL)")
            throw SourceManagementServiceError.duplicateFeed(command.preview.resolvedFeedURL)
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
                iconURL: command.preview.iconURL,
                language: command.preview.language,
                kind: command.preview.kind,
                folder: folder,
                createdAt: command.createdAt,
                updatedAt: command.createdAt
            )
        )

        return summaryMapper.feedSummary(from: feed)
    }

    func updateFeed(_ command: SourceManagementUpdateFeedCommand) throws -> SourceManagementFeedSummary {
        guard let currentFeed = try feedRepository.fetchFeed(id: command.feedID) else {
            logger.error("Skipped feed update because feed was not found: \(command.feedID.uuidString)")
            throw SourceManagementServiceError.feedNotFound(command.feedID)
        }

        if let preview = command.preview,
           let duplicateFeed = try normalizationPolicy.existingFeed(
            resolvedFeedURL: preview.resolvedFeedURL,
            requestedURL: preview.requestedURL
           ), duplicateFeed.id != command.feedID {
            logger.error("Skipped feed update because another feed already uses URL: \(preview.resolvedFeedURL)")
            throw SourceManagementServiceError.duplicateFeed(preview.resolvedFeedURL)
        }

        let folder = try normalizationPolicy.resolveFolder(for: command.folderPlacement)
        let displayTitleOverride = normalizationPolicy.normalizedDisplayTitle(command.displayTitleOverride)
        let metadataTitle = command.preview?.title ?? currentFeed.title
        try normalizationPolicy.ensureUniqueFeedDisplayTitle(displayTitleOverride ?? metadataTitle, excluding: command.feedID)

        do {
            let updatedFeed = try feedRepository.updateDetails(
                for: command.feedID,
                with: FeedDetailsUpdate(
                    url: command.preview?.resolvedFeedURL,
                    siteURL: command.preview?.siteURL,
                    title: command.preview?.title,
                    displayTitleOverride: displayTitleOverride,
                    clearsDisplayTitleOverride: displayTitleOverride == nil,
                    subtitle: command.preview?.subtitle,
                    iconURL: command.preview?.iconURL,
                    language: command.preview?.language,
                    kind: command.preview?.kind,
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
                from: try normalizationPolicy.requireFeedSummarySource(
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
            throw SourceManagementServiceError.feedNotFound(feedID)
        }
    }
}
