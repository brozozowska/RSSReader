import Foundation

enum SourceManagementServiceError: Error, Equatable {
    case invalidFeedURL(String)
    case feedDiscoveryFailed(String)
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

struct SourceManagementFeedDiscoveryPlan: Equatable, Sendable {
    let displayURL: String
    let feedURLs: [URL]
    let siteURLs: [URL]
    let fallbackFeedURLs: [URL]
}

enum SourceManagementFeedDiscoveryPlanner {
    static func makePlan(for input: String) throws -> SourceManagementFeedDiscoveryPlan {
        let normalizedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedInput.isEmpty == false else {
            throw SourceManagementServiceError.invalidFeedURL(input)
        }

        let inputURLs = try normalizedInputURLs(from: normalizedInput, originalInput: input)
        var feedURLs: [URL] = []
        var siteURLs: [URL] = []
        var fallbackFeedURLs: [URL] = []

        for inputURL in inputURLs {
            siteURLs.append(inputURL)

            guard let originURL = originURL(for: inputURL) else { continue }
            siteURLs.append(originURL)

            if isBareSiteURL(inputURL) {
                for path in commonFeedPaths {
                    if let feedURL = URL(string: path, relativeTo: originURL)?.absoluteURL {
                        feedURLs.append(feedURL)
                    }
                }
                fallbackFeedURLs.append(inputURL)
            } else {
                feedURLs.append(inputURL)
            }
        }

        let deduplicatedFeedURLs = deduplicate(feedURLs)
        let deduplicatedFallbackFeedURLs = deduplicate(fallbackFeedURLs)
        return SourceManagementFeedDiscoveryPlan(
            displayURL: inputURLs[0].absoluteString,
            feedURLs: deduplicatedFeedURLs,
            siteURLs: deduplicate(siteURLs),
            fallbackFeedURLs: deduplicatedFallbackFeedURLs
        )
    }

    static func displayURLString(for input: String) -> String? {
        try? makePlan(for: input).displayURL
    }

    static func autodiscoveredFeedURLs(in html: String, baseURL: URL) -> [URL] {
        guard let linkTagExpression = try? NSRegularExpression(
            pattern: #"<link\b[^>]*>"#,
            options: [.caseInsensitive]
        ) else {
            return []
        }

        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
        let urls = linkTagExpression.matches(in: html, range: nsRange).compactMap { match -> URL? in
            guard let tagRange = Range(match.range, in: html) else { return nil }
            let attributes = linkTagAttributes(in: String(html[tagRange]))
            guard let href = attributes["href"],
                  let rel = attributes["rel"]?.lowercased(),
                  rel.split(whereSeparator: \.isWhitespace).contains("alternate"),
                  isSupportedFeedLinkType(attributes["type"]) else {
                return nil
            }

            return URL(string: href, relativeTo: baseURL)?.absoluteURL
        }

        return deduplicate(urls)
    }

    private static let commonFeedPaths = [
        "/feed",
        "/rss",
        "/rss.xml",
        "/feed.xml",
        "/atom.xml"
    ]

    private static func normalizedInputURLs(
        from normalizedInput: String,
        originalInput: String
    ) throws -> [URL] {
        if let explicitURL = URL(string: normalizedInput),
           let scheme = explicitURL.scheme?.lowercased(),
           scheme.isEmpty == false {
            guard ["http", "https"].contains(scheme),
                  explicitURL.host?.isEmpty == false else {
                throw SourceManagementServiceError.invalidFeedURL(originalInput)
            }
            return [explicitURL]
        }

        let candidateStrings = [
            "https://\(normalizedInput)",
            "http://\(normalizedInput)"
        ]

        let urls = candidateStrings.compactMap { candidate in
            URL(string: candidate)
        }
        .filter { url in
            guard let scheme = url.scheme?.lowercased(),
                  ["http", "https"].contains(scheme),
                  url.host?.isEmpty == false else {
                return false
            }
            return true
        }

        guard urls.isEmpty == false else {
            throw SourceManagementServiceError.invalidFeedURL(originalInput)
        }

        return urls
    }

    private static func originURL(for url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.isEmpty == false,
              components.host?.isEmpty == false else {
            return nil
        }

        components.path = "/"
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private static func isBareSiteURL(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }

        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return path.isEmpty && components.query == nil && components.fragment == nil
    }

    private static func linkTagAttributes(in tag: String) -> [String: String] {
        guard let attributeExpression = try? NSRegularExpression(
            pattern: #"([A-Za-z_:][-A-Za-z0-9_:.]*)\s*=\s*("[^"]*"|'[^']*'|[^\s"'>]+)"#,
            options: [.caseInsensitive]
        ) else {
            return [:]
        }

        let nsRange = NSRange(tag.startIndex..<tag.endIndex, in: tag)
        return attributeExpression.matches(in: tag, range: nsRange).reduce(into: [String: String]()) { result, match in
            guard match.numberOfRanges == 3,
                  let nameRange = Range(match.range(at: 1), in: tag),
                  let valueRange = Range(match.range(at: 2), in: tag) else {
                return
            }

            let name = String(tag[nameRange]).lowercased()
            let rawValue = String(tag[valueRange])
            result[name] = unquotedAttributeValue(rawValue)
        }
    }

    private static func unquotedAttributeValue(_ value: String) -> String {
        guard value.count >= 2,
              let first = value.first,
              let last = value.last,
              (first == "\"" && last == "\"") || (first == "'" && last == "'") else {
            return value
        }

        return String(value.dropFirst().dropLast())
    }

    private static func isSupportedFeedLinkType(_ value: String?) -> Bool {
        guard let value else { return false }
        let normalizedValue = value
            .split(separator: ";", maxSplits: 1)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch normalizedValue {
        case "application/rss+xml",
                "application/atom+xml",
                "application/rdf+xml",
                "application/xml",
                "text/xml":
            return true
        default:
            return normalizedValue?.hasSuffix("+xml") == true
        }
    }

    private static func deduplicate(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { url in
            seen.insert(url.absoluteString).inserted
        }
    }
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
            try folderSummary(from: folder)
        }
    }

    func fetchFeeds() throws -> [SourceManagementFeedSummary] {
        try feedRepository.fetchAllFeeds().map(feedSummary(from:))
    }

    func fetchFeed(id: UUID) throws -> SourceManagementFeedSummary? {
        try feedRepository.fetchFeed(id: id).map(feedSummary(from:))
    }

    func fetchFolder(id: UUID) throws -> SourceManagementFolderSummary? {
        try folderRepository.fetchFolder(id: id).map { folder in
            try folderSummary(from: folder)
        }
    }

    func previewFeed(urlString: String) async throws -> SourceManagementFeedPreview {
        let discoveryPlan = try SourceManagementFeedDiscoveryPlanner.makePlan(for: urlString)
        var attemptedFeedURLs: Set<String> = []
        var lastPreviewError: Error?

        for feedURL in discoveryPlan.feedURLs {
            do {
                return try await previewFeed(at: feedURL)
            } catch {
                lastPreviewError = error
                attemptedFeedURLs.insert(feedURL.absoluteString)
                logger.debug("Source management feed discovery candidate failed for \(feedURL.absoluteString): \(error)")
            }
        }

        for siteURL in discoveryPlan.siteURLs {
            let discoveredFeedURLs = await discoverFeedURLs(from: siteURL)
            for feedURL in discoveredFeedURLs where attemptedFeedURLs.contains(feedURL.absoluteString) == false {
                do {
                    return try await previewFeed(at: feedURL)
                } catch {
                    lastPreviewError = error
                    attemptedFeedURLs.insert(feedURL.absoluteString)
                    logger.debug("Source management autodiscovered feed candidate failed for \(feedURL.absoluteString): \(error)")
                }
            }
        }

        for feedURL in discoveryPlan.fallbackFeedURLs where attemptedFeedURLs.contains(feedURL.absoluteString) == false {
            do {
                return try await previewFeed(at: feedURL)
            } catch {
                lastPreviewError = error
                attemptedFeedURLs.insert(feedURL.absoluteString)
                logger.debug("Source management fallback feed discovery candidate failed for \(feedURL.absoluteString): \(error)")
            }
        }

        if discoveryPlan.fallbackFeedURLs.isEmpty == false {
            throw SourceManagementServiceError.feedDiscoveryFailed(urlString)
        }

        if let lastPreviewError {
            throw lastPreviewError
        }

        throw SourceManagementServiceError.feedDiscoveryFailed(urlString)
    }

    private func previewFeed(at feedURL: URL) async throws -> SourceManagementFeedPreview {
        let normalizedURL = feedURL.absoluteString
        let request = FeedRequest(
            feedID: UUID(),
            url: feedURL,
            timeoutInterval: Self.previewRequestTimeoutInterval
        )
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

    private func discoverFeedURLs(from siteURL: URL) async -> [URL] {
        do {
            let response = try await httpClient.execute(
                HTTPRequest(
                    url: siteURL,
                    headers: [
                        "Accept": "text/html, application/xhtml+xml;q=0.9, */*;q=0.1",
                        "User-Agent": "RSSReader/0 (Feed Discovery)"
                    ],
                    timeoutInterval: Self.previewRequestTimeoutInterval
                )
            )
            guard (200...299).contains(response.statusCode),
                  let html = String(data: response.body, encoding: .utf8) else {
                return []
            }
            return SourceManagementFeedDiscoveryPlanner.autodiscoveredFeedURLs(
                in: html,
                baseURL: response.url
            )
        } catch {
            logger.debug("Source management HTML feed autodiscovery failed for \(siteURL.absoluteString): \(error)")
            return []
        }
    }

    private static let previewRequestTimeoutInterval: TimeInterval = 8

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

        return try folderSummary(from: folder)
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

        return try folderSummary(from: folder)
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
            if let finalFeed {
                _ = try articleRepository.refreshFeedProjection(for: finalFeed, saveAfterOperation: false)
            }
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
        if let feed {
            _ = try articleRepository.refreshFeedProjection(for: feed, saveAfterOperation: false)
            try feedRepository.save()
        }

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

    func folderSummary(from folder: Folder) throws -> SourceManagementFolderSummary {
        SourceManagementFolderSummary(
            id: folder.id,
            name: folder.name,
            sortOrder: folder.sortOrder,
            feedCount: try feedRepository.countFeeds(inFolderID: folder.id)
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
