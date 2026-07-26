import Foundation

enum FeedManagementServiceError: Error, Equatable {
    case invalidFeedURL(String)
    case feedDiscoveryFailed(String)
    case previewUnavailableForNotModifiedResponse
    case duplicateFeed(String)
    case duplicateFeedDisplayName(String)
    case emptyFolderName
    case duplicateFolderName(String)
    case feedNotFound(UUID)
    case folderNotFound(UUID)
}

enum FeedManagementFolderPlacement: Hashable, Sendable {
    case ungrouped
    case folder(UUID)
}

nonisolated struct FeedManagementFolderSummary: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let sortOrder: Int
    let feedCount: Int
}

nonisolated struct FeedManagementFeedSummary: Identifiable, Equatable, Sendable {
    let id: UUID
    let url: String
    let title: String
    let metadataTitle: String
    let displayTitleOverride: String?
    let folderID: UUID?
    let folderName: String?

    init(
        id: UUID,
        url: String,
        title: String,
        metadataTitle: String? = nil,
        displayTitleOverride: String? = nil,
        folderID: UUID?,
        folderName: String?
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.metadataTitle = metadataTitle ?? title
        self.displayTitleOverride = displayTitleOverride
        self.folderID = folderID
        self.folderName = folderName
    }
}

struct FeedManagementFeedPreview: Equatable, Sendable {
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

struct FeedManagementFeedDiscoveryPlan: Equatable, Sendable {
    let displayURL: String
    let feedURLs: [URL]
    let siteURLs: [URL]
    let fallbackFeedURLs: [URL]
}

struct FeedManagementCreateFolderCommand: Equatable, Sendable {
    let name: String
    let createdAt: Date

    init(name: String, createdAt: Date = .now) {
        self.name = name
        self.createdAt = createdAt
    }
}

struct FeedManagementCreateFeedCommand: Equatable, Sendable {
    let preview: FeedManagementFeedPreview
    let displayTitleOverride: String?
    let folderPlacement: FeedManagementFolderPlacement
    let createdAt: Date

    init(
        preview: FeedManagementFeedPreview,
        displayTitleOverride: String? = nil,
        folderPlacement: FeedManagementFolderPlacement,
        createdAt: Date = .now
    ) {
        self.preview = preview
        self.displayTitleOverride = displayTitleOverride
        self.folderPlacement = folderPlacement
        self.createdAt = createdAt
    }
}

struct FeedManagementMoveFeedCommand: Equatable, Sendable {
    let feedID: UUID
    let folderPlacement: FeedManagementFolderPlacement
    let updatedAt: Date

    init(
        feedID: UUID,
        folderPlacement: FeedManagementFolderPlacement,
        updatedAt: Date = .now
    ) {
        self.feedID = feedID
        self.folderPlacement = folderPlacement
        self.updatedAt = updatedAt
    }
}

struct FeedManagementUpdateFeedCommand: Equatable, Sendable {
    let feedID: UUID
    let preview: FeedManagementFeedPreview?
    let displayTitleOverride: String?
    let folderPlacement: FeedManagementFolderPlacement
    let updatedAt: Date

    init(
        feedID: UUID,
        preview: FeedManagementFeedPreview? = nil,
        displayTitleOverride: String? = nil,
        folderPlacement: FeedManagementFolderPlacement,
        updatedAt: Date = .now
    ) {
        self.feedID = feedID
        self.preview = preview
        self.displayTitleOverride = displayTitleOverride
        self.folderPlacement = folderPlacement
        self.updatedAt = updatedAt
    }
}

struct FeedManagementUpdateFolderCommand: Equatable, Sendable {
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
protocol FeedManagementService {
    func fetchFolders() throws -> [FeedManagementFolderSummary]
    func fetchFeeds() throws -> [FeedManagementFeedSummary]
    func fetchFeed(id: UUID) throws -> FeedManagementFeedSummary?
    func fetchFolder(id: UUID) throws -> FeedManagementFolderSummary?
    func previewFeed(urlString: String) async throws -> FeedManagementFeedPreview
    func createFolder(_ command: FeedManagementCreateFolderCommand) throws -> FeedManagementFolderSummary
    func updateFolder(_ command: FeedManagementUpdateFolderCommand) throws -> FeedManagementFolderSummary
    func deleteFolder(id: UUID) throws
    func createFeed(_ command: FeedManagementCreateFeedCommand) throws -> FeedManagementFeedSummary
    func updateFeed(_ command: FeedManagementUpdateFeedCommand) throws -> FeedManagementFeedSummary
    func deleteFeed(id: UUID) throws
    func moveFeed(_ command: FeedManagementMoveFeedCommand) throws -> FeedManagementFeedSummary
}

@MainActor
final class DefaultFeedManagementService: FeedManagementService {
    private let logger: Logging
    private let httpClient: any HTTPClient
    private let feedFetcher: any FeedFetching
    private let feedParsingWorker: any FeedParsingWorking
    private let feedRepository: any FeedRepository
    private let folderRepository: any FolderRepository
    private let articleRepository: any ArticleRepository

    init(
        logger: Logging,
        httpClient: any HTTPClient,
        feedFetcher: any FeedFetching,
        feedParsingWorker: any FeedParsingWorking = FeedParsingWorker(),
        feedRepository: any FeedRepository,
        folderRepository: any FolderRepository,
        articleRepository: any ArticleRepository
    ) {
        self.logger = logger
        self.httpClient = httpClient
        self.feedFetcher = feedFetcher
        self.feedParsingWorker = feedParsingWorker
        self.feedRepository = feedRepository
        self.folderRepository = folderRepository
        self.articleRepository = articleRepository
    }

    func fetchFolders() throws -> [FeedManagementFolderSummary] {
        try folderRepository.fetchAllFolders().map { folder in
            try summaryMapper.folderSummary(from: folder)
        }
    }

    func fetchFeeds() throws -> [FeedManagementFeedSummary] {
        try feedRepository.fetchAllFeeds().map(summaryMapper.feedSummary(from:))
    }

    func fetchFeed(id: UUID) throws -> FeedManagementFeedSummary? {
        try feedRepository.fetchFeed(id: id).map(summaryMapper.feedSummary(from:))
    }

    func fetchFolder(id: UUID) throws -> FeedManagementFolderSummary? {
        try folderRepository.fetchFolder(id: id).map { folder in
            try summaryMapper.folderSummary(from: folder)
        }
    }

    func previewFeed(urlString: String) async throws -> FeedManagementFeedPreview {
        try await feedPreviewService.previewFeed(urlString: urlString)
    }

    func createFolder(_ command: FeedManagementCreateFolderCommand) throws -> FeedManagementFolderSummary {
        try folderCommandPersistence.createFolder(command)
    }

    func updateFolder(_ command: FeedManagementUpdateFolderCommand) throws -> FeedManagementFolderSummary {
        try folderCommandPersistence.updateFolder(command)
    }

    func deleteFolder(id folderID: UUID) throws {
        try folderCommandPersistence.deleteFolder(id: folderID)
    }

    func createFeed(_ command: FeedManagementCreateFeedCommand) throws -> FeedManagementFeedSummary {
        try feedCommandPersistence.createFeed(command)
    }

    func updateFeed(_ command: FeedManagementUpdateFeedCommand) throws -> FeedManagementFeedSummary {
        try feedCommandPersistence.updateFeed(command)
    }

    func deleteFeed(id feedID: UUID) throws {
        try feedCommandPersistence.deleteFeed(id: feedID)
    }

    func moveFeed(_ command: FeedManagementMoveFeedCommand) throws -> FeedManagementFeedSummary {
        try moveFeedFlow.moveFeed(command)
    }

    private var summaryMapper: FeedManagementSummaryMapper {
        FeedManagementSummaryMapper(feedRepository: feedRepository)
    }

    private var normalizationPolicy: FeedManagementNormalizationPolicy {
        FeedManagementNormalizationPolicy(
            logger: logger,
            feedRepository: feedRepository,
            folderRepository: folderRepository
        )
    }

    private var feedPreviewService: FeedManagementFeedPreviewService {
        FeedManagementFeedPreviewService(
            logger: logger,
            httpClient: httpClient,
            feedFetcher: feedFetcher,
            feedParsingWorker: feedParsingWorker,
            normalizationPolicy: normalizationPolicy
        )
    }

    private var folderCommandPersistence: FeedManagementFolderCommandPersistence {
        FeedManagementFolderCommandPersistence(
            logger: logger,
            feedRepository: feedRepository,
            folderRepository: folderRepository,
            articleRepository: articleRepository,
            normalizationPolicy: normalizationPolicy,
            summaryMapper: summaryMapper
        )
    }

    private var feedCommandPersistence: FeedManagementFeedCommandPersistence {
        FeedManagementFeedCommandPersistence(
            logger: logger,
            feedRepository: feedRepository,
            articleRepository: articleRepository,
            normalizationPolicy: normalizationPolicy,
            summaryMapper: summaryMapper
        )
    }

    private var moveFeedFlow: FeedManagementMoveFeedFlow {
        FeedManagementMoveFeedFlow(
            logger: logger,
            feedRepository: feedRepository,
            articleRepository: articleRepository,
            normalizationPolicy: normalizationPolicy,
            summaryMapper: summaryMapper
        )
    }
}
