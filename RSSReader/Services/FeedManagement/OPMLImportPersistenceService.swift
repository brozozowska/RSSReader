import Foundation

struct OPMLImportPersistenceResult: Equatable, Sendable {
    let createdFolders: [FeedManagementFolderSummary]
    let createdFeeds: [FeedManagementFeedSummary]
    let skippedEntries: [OPMLImportSkippedEntryDTO]

    var createdFolderCount: Int {
        createdFolders.count
    }

    var createdFeedCount: Int {
        createdFeeds.count
    }

    var skippedEntryCount: Int {
        skippedEntries.count
    }
}

struct OPMLImportSkippedEntryDTO: Equatable, Sendable {
    let entryID: OPMLImportPreviewEntryDTO.ID
    let displayTitle: String
    let reason: OPMLImportSkippedReason
}

enum OPMLImportSkippedReason: Equatable, Sendable {
    case previewIssues([OPMLImportPreviewIssue])
    case feedManagementRejected(FeedManagementServiceError)
}

enum OPMLImportPersistenceService {
    @MainActor
    static func importPreview(
        _ plan: OPMLImportPreviewPlan,
        feedManagementService: any FeedManagementService,
        importedAt: Date = .now
    ) throws -> OPMLImportPersistenceResult {
        var folderCache = try OPMLImportFolderCache(
            folders: feedManagementService.fetchFolders()
        )
        var createdFolders: [FeedManagementFolderSummary] = []
        var createdFeeds: [FeedManagementFeedSummary] = []
        var skippedEntries: [OPMLImportSkippedEntryDTO] = []

        for entry in plan.entries {
            guard entry.isImportable else {
                skippedEntries.append(
                    OPMLImportSkippedEntryDTO(
                        entryID: entry.id,
                        displayTitle: entry.displayTitle,
                        reason: .previewIssues(entry.issues)
                    )
                )
                continue
            }

            let folderPlacement = try resolveFolderPlacement(
                for: entry,
                feedManagementService: feedManagementService,
                folderCache: &folderCache,
                createdFolders: &createdFolders,
                importedAt: importedAt
            )

            do {
                let createdFeed = try feedManagementService.createFeed(
                    FeedManagementCreateFeedCommand(
                        preview: feedManagementFeedPreview(from: entry),
                        folderPlacement: folderPlacement,
                        createdAt: importedAt
                    )
                )
                createdFeeds.append(createdFeed)
            } catch let error as FeedManagementServiceError where error.isImportSkipReason {
                skippedEntries.append(
                    OPMLImportSkippedEntryDTO(
                        entryID: entry.id,
                        displayTitle: entry.displayTitle,
                        reason: .feedManagementRejected(error)
                    )
                )
            }
        }

        return OPMLImportPersistenceResult(
            createdFolders: createdFolders,
            createdFeeds: createdFeeds,
            skippedEntries: skippedEntries
        )
    }

    @MainActor
    private static func resolveFolderPlacement(
        for entry: OPMLImportPreviewEntryDTO,
        feedManagementService: any FeedManagementService,
        folderCache: inout OPMLImportFolderCache,
        createdFolders: inout [FeedManagementFolderSummary],
        importedAt: Date
    ) throws -> FeedManagementFolderPlacement {
        switch entry.folderResolution {
        case .ungrouped:
            return .ungrouped
        case .existingFolder(let id, _):
            return .folder(id)
        case .newFolder(let name):
            if let cachedFolder = folderCache.folder(named: name) {
                return .folder(cachedFolder.id)
            }

            do {
                let createdFolder = try feedManagementService.createFolder(
                    FeedManagementCreateFolderCommand(
                        name: name,
                        createdAt: importedAt
                    )
                )
                folderCache.insert(createdFolder)
                createdFolders.append(createdFolder)
                return .folder(createdFolder.id)
            } catch FeedManagementServiceError.duplicateFolderName {
                let refreshedCache = try OPMLImportFolderCache(
                    folders: feedManagementService.fetchFolders()
                )
                folderCache = refreshedCache
                if let existingFolder = folderCache.folder(named: name) {
                    return .folder(existingFolder.id)
                }
                throw FeedManagementServiceError.duplicateFolderName(name)
            }
        }
    }

    private static func feedManagementFeedPreview(
        from entry: OPMLImportPreviewEntryDTO
    ) -> FeedManagementFeedPreview {
        let feedURL = entry.normalizedFeedURL ?? entry.outline.xmlURL
        return FeedManagementFeedPreview(
            requestedURL: feedURL,
            resolvedFeedURL: feedURL,
            title: entry.displayTitle,
            subtitle: nil,
            siteURL: normalizedSiteURL(entry.outline.htmlURL),
            iconURL: nil,
            language: nil,
            kind: .unknown,
            parserAnomalyCount: 0,
            rejectedEntryCount: 0,
            existingFeedID: nil
        )
    }

    private static func normalizedSiteURL(_ value: String?) -> String? {
        guard let normalizedURL = FeedURLNormalizer.normalizeSourceURL(value),
              FeedURLNormalizer.hasAbsoluteWebURL(normalizedURL) else {
            return nil
        }

        return normalizedURL
    }
}

private struct OPMLImportFolderCache {
    private var foldersByName: [String: FeedManagementFolderSummary]

    init(folders: [FeedManagementFolderSummary]) throws {
        foldersByName = [:]
        for folder in folders {
            foldersByName[Self.comparisonKey(folder.name)] = folder
        }
    }

    func folder(named name: String) -> FeedManagementFolderSummary? {
        foldersByName[Self.comparisonKey(name)]
    }

    mutating func insert(_ folder: FeedManagementFolderSummary) {
        foldersByName[Self.comparisonKey(folder.name)] = folder
    }

    private static func comparisonKey(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

private extension FeedManagementServiceError {
    var isImportSkipReason: Bool {
        switch self {
        case .duplicateFeed, .duplicateFeedDisplayName:
            return true
        default:
            return false
        }
    }
}
