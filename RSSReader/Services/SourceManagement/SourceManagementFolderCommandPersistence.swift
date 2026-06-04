import Foundation

@MainActor
struct SourceManagementFolderCommandPersistence {
    let logger: Logging
    let feedRepository: any FeedRepository
    let folderRepository: any FolderRepository
    let articleRepository: any ArticleRepository
    let normalizationPolicy: SourceManagementNormalizationPolicy
    let summaryMapper: SourceManagementSummaryMapper

    func createFolder(_ command: SourceManagementCreateFolderCommand) throws -> SourceManagementFolderSummary {
        let normalizedName = try normalizationPolicy.normalizedFolderName(command.name)

        if try folderRepository.fetchFolder(name: normalizedName) != nil {
            logger.error("Skipped folder creation because folder already exists: \(normalizedName)")
            throw SourceManagementServiceError.duplicateFolderName(normalizedName)
        }

        let nextSortOrder = try folderRepository.fetchAllFolders()
            .map(\.sortOrder)
            .max()
            .map { $0 + 1 } ?? 0

        let folder = try folderRepository.insert(
            Folder(
                name: normalizedName,
                sortOrder: nextSortOrder,
                createdAt: command.createdAt,
                updatedAt: command.createdAt
            )
        )

        return try summaryMapper.folderSummary(from: folder)
    }

    func updateFolder(_ command: SourceManagementUpdateFolderCommand) throws -> SourceManagementFolderSummary {
        let normalizedName = try normalizationPolicy.normalizedFolderName(command.name)

        guard try folderRepository.fetchFolder(id: command.folderID) != nil else {
            logger.error("Skipped folder update because folder was not found: \(command.folderID.uuidString)")
            throw SourceManagementServiceError.folderNotFound(command.folderID)
        }

        if let existingFolder = try folderRepository.fetchFolder(name: normalizedName),
           existingFolder.id != command.folderID {
            logger.error("Skipped folder update because another folder already uses name: \(normalizedName)")
            throw SourceManagementServiceError.duplicateFolderName(normalizedName)
        }

        guard let folder = try folderRepository.update(
            folderID: command.folderID,
            with: FolderDetailsUpdate(
                name: normalizedName,
                updatedAt: command.updatedAt
            ),
            saveAfterOperation: false
        ) else {
            logger.error("Skipped folder update because update path returned no folder: \(command.folderID.uuidString)")
            throw SourceManagementServiceError.folderNotFound(command.folderID)
        }

        let feedsInFolder = try feedRepository.fetchAllFeeds()
            .filter { $0.folder?.id == folder.id }
        for feed in feedsInFolder {
            _ = try articleRepository.refreshFeedProjection(for: feed, saveAfterOperation: false)
        }
        try folderRepository.save()

        return try summaryMapper.folderSummary(from: folder)
    }

    func deleteFolder(id folderID: UUID) throws {
        guard let folder = try folderRepository.fetchFolder(id: folderID) else {
            logger.error("Skipped folder deletion because folder was not found: \(folderID.uuidString)")
            throw SourceManagementServiceError.folderNotFound(folderID)
        }

        let containedFeedIDs = try feedRepository.fetchAllFeeds()
            .filter { $0.folder?.id == folderID }
            .map(\.id)

        do {
            for feedID in containedFeedIDs {
                if let updatedFeed = try feedRepository.updateFolderAssignment(
                    for: feedID,
                    with: FeedFolderAssignmentUpdate(
                        folder: nil,
                        updatedAt: .now
                    ),
                    saveAfterOperation: false
                ) {
                    _ = try articleRepository.refreshFeedProjection(for: updatedFeed, saveAfterOperation: false)
                }
            }
            try folderRepository.delete(folder)
        } catch {
            feedRepository.rollback()
            throw error
        }
    }
}
