import Foundation

enum SourceManagementServiceError: Error, Equatable {
    case invalidFeedURL(String)
    case previewUnavailableForNotModifiedResponse
    case duplicateFeed(String)
    case emptyFolderName
    case duplicateFolderName(String)
    case feedNotFound(UUID)
    case folderNotFound(UUID)
}

enum SourceManagementFolderPlacement: Hashable, Sendable {
    case ungrouped
    case folder(UUID)
}

struct SourceManagementFolderSummary: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let sortOrder: Int
    let feedCount: Int
}

struct SourceManagementFeedSummary: Identifiable, Equatable, Sendable {
    let id: UUID
    let url: String
    let title: String
    let folderID: UUID?
    let folderName: String?
}

struct SourceManagementFeedPreview: Equatable, Sendable {
    let requestedURL: String
    let resolvedFeedURL: String
    let title: String
    let subtitle: String?
    let siteURL: String?
    let iconURL: String?
    let language: String?
    let kind: FeedKind
    let parserAnomalyCount: Int
    let rejectedEntryCount: Int
    let existingFeedID: UUID?
}

struct SourceManagementCreateFolderCommand: Equatable, Sendable {
    let name: String
    let createdAt: Date

    init(name: String, createdAt: Date = .now) {
        self.name = name
        self.createdAt = createdAt
    }
}

struct SourceManagementCreateFeedCommand: Equatable, Sendable {
    let preview: SourceManagementFeedPreview
    let folderPlacement: SourceManagementFolderPlacement
    let createdAt: Date

    init(
        preview: SourceManagementFeedPreview,
        folderPlacement: SourceManagementFolderPlacement,
        createdAt: Date = .now
    ) {
        self.preview = preview
        self.folderPlacement = folderPlacement
        self.createdAt = createdAt
    }
}

struct SourceManagementMoveFeedCommand: Equatable, Sendable {
    let feedID: UUID
    let folderPlacement: SourceManagementFolderPlacement
    let updatedAt: Date

    init(
        feedID: UUID,
        folderPlacement: SourceManagementFolderPlacement,
        updatedAt: Date = .now
    ) {
        self.feedID = feedID
        self.folderPlacement = folderPlacement
        self.updatedAt = updatedAt
    }
}

struct SourceManagementUpdateFeedCommand: Equatable, Sendable {
    let feedID: UUID
    let preview: SourceManagementFeedPreview
    let folderPlacement: SourceManagementFolderPlacement
    let updatedAt: Date

    init(
        feedID: UUID,
        preview: SourceManagementFeedPreview,
        folderPlacement: SourceManagementFolderPlacement,
        updatedAt: Date = .now
    ) {
        self.feedID = feedID
        self.preview = preview
        self.folderPlacement = folderPlacement
        self.updatedAt = updatedAt
    }
}

struct SourceManagementUpdateFolderCommand: Equatable, Sendable {
    let folderID: UUID
    let name: String
    let updatedAt: Date

    init(
        folderID: UUID,
        name: String,
        updatedAt: Date = .now
    ) {
        self.folderID = folderID
        self.name = name
        self.updatedAt = updatedAt
    }
}

@MainActor
protocol SourceManagementService {
    func fetchFolders() throws -> [SourceManagementFolderSummary]
    func fetchFeeds() throws -> [SourceManagementFeedSummary]
    func fetchFeed(id: UUID) throws -> SourceManagementFeedSummary?
    func fetchFolder(id: UUID) throws -> SourceManagementFolderSummary?
    func previewFeed(urlString: String) async throws -> SourceManagementFeedPreview
    func createFolder(_ command: SourceManagementCreateFolderCommand) throws -> SourceManagementFolderSummary
    func updateFolder(_ command: SourceManagementUpdateFolderCommand) throws -> SourceManagementFolderSummary
    func deleteFolder(id: UUID) throws
    func createFeed(_ command: SourceManagementCreateFeedCommand) throws -> SourceManagementFeedSummary
    func updateFeed(_ command: SourceManagementUpdateFeedCommand) throws -> SourceManagementFeedSummary
    func deleteFeed(id: UUID) throws
    func moveFeed(_ command: SourceManagementMoveFeedCommand) throws -> SourceManagementFeedSummary
}

@MainActor
final class DefaultSourceManagementService: SourceManagementService {
    private let logger: Logging
    private let feedFetcher: any FeedFetching
    private let feedRepository: any FeedRepository
    private let folderRepository: any FolderRepository

    init(
        logger: Logging,
        feedFetcher: any FeedFetching,
        feedRepository: any FeedRepository,
        folderRepository: any FolderRepository
    ) {
        self.logger = logger
        self.feedFetcher = feedFetcher
        self.feedRepository = feedRepository
        self.folderRepository = folderRepository
    }

    func fetchFolders() throws -> [SourceManagementFolderSummary] {
        try folderRepository.fetchAllFolders().map(folderSummary(from:))
    }

    func fetchFeeds() throws -> [SourceManagementFeedSummary] {
        try feedRepository.fetchAllFeeds().map(feedSummary(from:))
    }

    func fetchFeed(id: UUID) throws -> SourceManagementFeedSummary? {
        try feedRepository.fetchFeed(id: id).map(feedSummary(from:))
    }

    func fetchFolder(id: UUID) throws -> SourceManagementFolderSummary? {
        try folderRepository.fetchFolder(id: id).map(folderSummary(from:))
    }

    func previewFeed(urlString: String) async throws -> SourceManagementFeedPreview {
        let normalizedURL = try normalizedFeedURLString(urlString)
        let request: FeedRequest

        do {
            request = try FeedRequest(feedID: UUID(), urlString: normalizedURL)
        } catch {
            logger.error("Skipped source management preview because feed URL is invalid: \(normalizedURL)")
            throw SourceManagementServiceError.invalidFeedURL(urlString)
        }

        let fetchResult = try await feedFetcher.fetch(request)
        guard case .fetched(let response) = fetchResult else {
            logger.error("Skipped source management preview because fetch returned not-modified for \(normalizedURL)")
            throw SourceManagementServiceError.previewUnavailableForNotModifiedResponse
        }

        let pipelineResult = try FeedParserService.parsePipelineResult(response)
        let metadata = pipelineResult.feed.metadata
        let resolvedFeedURL = response.sourceURL.absoluteString
        let existingFeed = try existingFeed(
            resolvedFeedURL: resolvedFeedURL,
            requestedURL: normalizedURL
        )

        return SourceManagementFeedPreview(
            requestedURL: normalizedURL,
            resolvedFeedURL: resolvedFeedURL,
            title: normalizedNonEmptyString(metadata.title) ?? resolvedFeedURL,
            subtitle: normalizedNonEmptyString(metadata.subtitle),
            siteURL: normalizedNonEmptyString(metadata.siteURL),
            iconURL: normalizedNonEmptyString(metadata.iconURL),
            language: normalizedNonEmptyString(metadata.language),
            kind: pipelineResult.feed.kind,
            parserAnomalyCount: pipelineResult.diagnostics.parserAnomalies.count,
            rejectedEntryCount: pipelineResult.diagnostics.rejectedEntries.count,
            existingFeedID: existingFeed?.id
        )
    }

    func createFolder(_ command: SourceManagementCreateFolderCommand) throws -> SourceManagementFolderSummary {
        let normalizedName = try normalizedFolderName(command.name)

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

        return folderSummary(from: folder)
    }

    func updateFolder(_ command: SourceManagementUpdateFolderCommand) throws -> SourceManagementFolderSummary {
        let normalizedName = try normalizedFolderName(command.name)

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
            )
        ) else {
            logger.error("Skipped folder update because update path returned no folder: \(command.folderID.uuidString)")
            throw SourceManagementServiceError.folderNotFound(command.folderID)
        }

        return folderSummary(from: folder)
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
                _ = try feedRepository.updateFolderAssignment(
                    for: feedID,
                    with: FeedFolderAssignmentUpdate(
                        folder: nil,
                        updatedAt: .now
                    ),
                    saveAfterOperation: false
                )
            }
            try folderRepository.delete(folder)
        } catch {
            feedRepository.rollback()
            throw error
        }
    }

    func createFeed(_ command: SourceManagementCreateFeedCommand) throws -> SourceManagementFeedSummary {
        if try existingFeed(
            resolvedFeedURL: command.preview.resolvedFeedURL,
            requestedURL: command.preview.requestedURL
        ) != nil {
            logger.error("Skipped feed creation because feed already exists: \(command.preview.resolvedFeedURL)")
            throw SourceManagementServiceError.duplicateFeed(command.preview.resolvedFeedURL)
        }

        let folder = try resolveFolder(for: command.folderPlacement)
        let feed = try feedRepository.insert(
            Feed(
                url: command.preview.resolvedFeedURL,
                siteURL: command.preview.siteURL,
                title: command.preview.title,
                subtitle: command.preview.subtitle,
                iconURL: command.preview.iconURL,
                language: command.preview.language,
                kind: command.preview.kind,
                folder: folder,
                createdAt: command.createdAt,
                updatedAt: command.createdAt
            )
        )

        return feedSummary(from: feed)
    }

    func updateFeed(_ command: SourceManagementUpdateFeedCommand) throws -> SourceManagementFeedSummary {
        guard try feedRepository.fetchMetadata(for: command.feedID) != nil else {
            logger.error("Skipped feed update because feed was not found: \(command.feedID.uuidString)")
            throw SourceManagementServiceError.feedNotFound(command.feedID)
        }

        if let duplicateFeed = try existingFeed(
            resolvedFeedURL: command.preview.resolvedFeedURL,
            requestedURL: command.preview.requestedURL
        ), duplicateFeed.id != command.feedID {
            logger.error("Skipped feed update because another feed already uses URL: \(command.preview.resolvedFeedURL)")
            throw SourceManagementServiceError.duplicateFeed(command.preview.resolvedFeedURL)
        }

        let folder = try resolveFolder(for: command.folderPlacement)

        do {
            let updatedFeed = try feedRepository.updateDetails(
                for: command.feedID,
                with: FeedDetailsUpdate(
                    url: command.preview.resolvedFeedURL,
                    siteURL: command.preview.siteURL,
                    title: command.preview.title,
                    subtitle: command.preview.subtitle,
                    iconURL: command.preview.iconURL,
                    language: command.preview.language,
                    kind: command.preview.kind,
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
            try feedRepository.save()
            return feedSummary(from: try requireFeedSummarySource(finalFeed, feedID: command.feedID))
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

    func moveFeed(_ command: SourceManagementMoveFeedCommand) throws -> SourceManagementFeedSummary {
        guard try feedRepository.fetchMetadata(for: command.feedID) != nil else {
            logger.error("Skipped feed move because feed was not found: \(command.feedID.uuidString)")
            throw SourceManagementServiceError.feedNotFound(command.feedID)
        }

        let folder = try resolveFolder(for: command.folderPlacement)
        let update = FeedFolderAssignmentUpdate(
            folder: folder,
            updatedAt: command.updatedAt
        )
        let feed = try feedRepository.updateFolderAssignment(
            for: command.feedID,
            with: update
        )

        return feedSummary(from: try requireFeedSummarySource(feed, feedID: command.feedID))
    }
}

private extension DefaultSourceManagementService {
    func requireFeedSummarySource(_ feed: Feed?, feedID: UUID) throws -> Feed {
        guard let feed else {
            logger.error("Skipped feed move because feed update path returned no feed: \(feedID.uuidString)")
            throw SourceManagementServiceError.feedNotFound(feedID)
        }
        return feed
    }

    func normalizedFeedURLString(_ value: String) throws -> String {
        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedValue.isEmpty == false else {
            throw SourceManagementServiceError.invalidFeedURL(value)
        }
        return normalizedValue
    }

    func normalizedFolderName(_ value: String) throws -> String {
        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedValue.isEmpty == false else {
            throw SourceManagementServiceError.emptyFolderName
        }
        return normalizedValue
    }

    func normalizedNonEmptyString(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedValue.isEmpty ? nil : normalizedValue
    }

    func existingFeed(resolvedFeedURL: String, requestedURL: String) throws -> Feed? {
        if let feed = try feedRepository.fetchFeed(url: resolvedFeedURL) {
            return feed
        }

        guard resolvedFeedURL != requestedURL else {
            return nil
        }

        return try feedRepository.fetchFeed(url: requestedURL)
    }

    func resolveFolder(for placement: SourceManagementFolderPlacement) throws -> Folder? {
        switch placement {
        case .ungrouped:
            return nil
        case .folder(let folderID):
            guard let folder = try folderRepository.fetchFolder(id: folderID) else {
                logger.error("Skipped source management operation because folder was not found: \(folderID.uuidString)")
                throw SourceManagementServiceError.folderNotFound(folderID)
            }
            return folder
        }
    }

    func folderSummary(from folder: Folder) -> SourceManagementFolderSummary {
        SourceManagementFolderSummary(
            id: folder.id,
            name: folder.name,
            sortOrder: folder.sortOrder,
            feedCount: folder.feeds.count
        )
    }

    func feedSummary(from feed: Feed) -> SourceManagementFeedSummary {
        SourceManagementFeedSummary(
            id: feed.id,
            url: feed.url,
            title: feed.title,
            folderID: feed.folder?.id,
            folderName: feed.folder?.name
        )
    }
}
