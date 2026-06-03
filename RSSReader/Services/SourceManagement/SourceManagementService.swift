import Foundation

enum SourceManagementServiceError: Error, Equatable {
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

struct SourceManagementFeedDiscoveryPlan: Equatable, Sendable {
    let displayURL: String
    let feedURLs: [URL]
    let siteURLs: [URL]
    let fallbackFeedURLs: [URL]
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
    let displayTitleOverride: String?
    let folderPlacement: SourceManagementFolderPlacement
    let createdAt: Date

    init(
        preview: SourceManagementFeedPreview,
        displayTitleOverride: String? = nil,
        folderPlacement: SourceManagementFolderPlacement,
        createdAt: Date = .now
    ) {
        self.preview = preview
        self.displayTitleOverride = displayTitleOverride
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
    let preview: SourceManagementFeedPreview?
    let displayTitleOverride: String?
    let folderPlacement: SourceManagementFolderPlacement
    let updatedAt: Date

    init(
        feedID: UUID,
        preview: SourceManagementFeedPreview? = nil,
        displayTitleOverride: String? = nil,
        folderPlacement: SourceManagementFolderPlacement,
        updatedAt: Date = .now
    ) {
        self.feedID = feedID
        self.preview = preview
        self.displayTitleOverride = displayTitleOverride
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
    private let httpClient: any HTTPClient
    private let feedFetcher: any FeedFetching
    private let feedRepository: any FeedRepository
    private let folderRepository: any FolderRepository
    private let articleRepository: any ArticleRepository

    init(
        logger: Logging,
        httpClient: any HTTPClient,
        feedFetcher: any FeedFetching,
        feedRepository: any FeedRepository,
        folderRepository: any FolderRepository,
        articleRepository: any ArticleRepository
    ) {
        self.logger = logger
        self.httpClient = httpClient
        self.feedFetcher = feedFetcher
        self.feedRepository = feedRepository
        self.folderRepository = folderRepository
        self.articleRepository = articleRepository
    }

    func fetchFolders() throws -> [SourceManagementFolderSummary] {
        try folderRepository.fetchAllFolders().map { folder in
            try summaryMapper.folderSummary(from: folder)
        }
    }

    func fetchFeeds() throws -> [SourceManagementFeedSummary] {
        try feedRepository.fetchAllFeeds().map(summaryMapper.feedSummary(from:))
    }

    func fetchFeed(id: UUID) throws -> SourceManagementFeedSummary? {
        try feedRepository.fetchFeed(id: id).map(summaryMapper.feedSummary(from:))
    }

    func fetchFolder(id: UUID) throws -> SourceManagementFolderSummary? {
        try folderRepository.fetchFolder(id: id).map { folder in
            try summaryMapper.folderSummary(from: folder)
        }
    }

    func previewFeed(urlString: String) async throws -> SourceManagementFeedPreview {
        try await feedPreviewService.previewFeed(urlString: urlString)
    }

    func createFolder(_ command: SourceManagementCreateFolderCommand) throws -> SourceManagementFolderSummary {
        try folderCommandPersistence.createFolder(command)
    }

    func updateFolder(_ command: SourceManagementUpdateFolderCommand) throws -> SourceManagementFolderSummary {
        try folderCommandPersistence.updateFolder(command)
    }

    func deleteFolder(id folderID: UUID) throws {
        try folderCommandPersistence.deleteFolder(id: folderID)
    }

    func createFeed(_ command: SourceManagementCreateFeedCommand) throws -> SourceManagementFeedSummary {
        try feedCommandPersistence.createFeed(command)
    }

    func updateFeed(_ command: SourceManagementUpdateFeedCommand) throws -> SourceManagementFeedSummary {
        try feedCommandPersistence.updateFeed(command)
    }

    func deleteFeed(id feedID: UUID) throws {
        try feedCommandPersistence.deleteFeed(id: feedID)
    }

    func moveFeed(_ command: SourceManagementMoveFeedCommand) throws -> SourceManagementFeedSummary {
        try moveFeedFlow.moveFeed(command)
    }

    private var summaryMapper: SourceManagementSummaryMapper {
        SourceManagementSummaryMapper(feedRepository: feedRepository)
    }

    private var normalizationPolicy: SourceManagementNormalizationPolicy {
        SourceManagementNormalizationPolicy(
            logger: logger,
            feedRepository: feedRepository,
            folderRepository: folderRepository
        )
    }

    private var feedPreviewService: SourceManagementFeedPreviewService {
        SourceManagementFeedPreviewService(
            logger: logger,
            httpClient: httpClient,
            feedFetcher: feedFetcher,
            normalizationPolicy: normalizationPolicy
        )
    }

    private var folderCommandPersistence: SourceManagementFolderCommandPersistence {
        SourceManagementFolderCommandPersistence(
            logger: logger,
            feedRepository: feedRepository,
            folderRepository: folderRepository,
            articleRepository: articleRepository,
            normalizationPolicy: normalizationPolicy,
            summaryMapper: summaryMapper
        )
    }

    private var feedCommandPersistence: SourceManagementFeedCommandPersistence {
        SourceManagementFeedCommandPersistence(
            logger: logger,
            feedRepository: feedRepository,
            articleRepository: articleRepository,
            normalizationPolicy: normalizationPolicy,
            summaryMapper: summaryMapper
        )
    }

    private var moveFeedFlow: SourceManagementMoveFeedFlow {
        SourceManagementMoveFeedFlow(
            logger: logger,
            feedRepository: feedRepository,
            articleRepository: articleRepository,
            normalizationPolicy: normalizationPolicy,
            summaryMapper: summaryMapper
        )
    }
}
