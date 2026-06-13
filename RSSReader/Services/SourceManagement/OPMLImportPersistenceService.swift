import Foundation

struct OPMLImportPersistenceResult: Equatable, Sendable {
    let createdFolders: [SourceManagementFolderSummary]
    let createdFeeds: [SourceManagementFeedSummary]
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
    case sourceManagementRejected(SourceManagementServiceError)
}

enum OPMLImportPersistenceService {
    @MainActor
    static func importPreview(
        _ plan: OPMLImportPreviewPlan,
        sourceManagementService: any SourceManagementService,
        importedAt: Date = .now
    ) throws -> OPMLImportPersistenceResult {
        var folderCache = try OPMLImportFolderCache(
            folders: sourceManagementService.fetchFolders()
        )
        var createdFolders: [SourceManagementFolderSummary] = []
        var createdFeeds: [SourceManagementFeedSummary] = []
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
                sourceManagementService: sourceManagementService,
                folderCache: &folderCache,
                createdFolders: &createdFolders,
                importedAt: importedAt
            )

            do {
                let createdFeed = try sourceManagementService.createFeed(
                    SourceManagementCreateFeedCommand(
                        preview: sourceManagementFeedPreview(from: entry),
                        folderPlacement: folderPlacement,
                        createdAt: importedAt
                    )
                )
                createdFeeds.append(createdFeed)
            } catch let error as SourceManagementServiceError where error.isImportSkipReason {
                skippedEntries.append(
                    OPMLImportSkippedEntryDTO(
                        entryID: entry.id,
                        displayTitle: entry.displayTitle,
                        reason: .sourceManagementRejected(error)
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
        sourceManagementService: any SourceManagementService,
        folderCache: inout OPMLImportFolderCache,
        createdFolders: inout [SourceManagementFolderSummary],
        importedAt: Date
    ) throws -> SourceManagementFolderPlacement {
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
                let createdFolder = try sourceManagementService.createFolder(
                    SourceManagementCreateFolderCommand(
                        name: name,
                        createdAt: importedAt
                    )
                )
                folderCache.insert(createdFolder)
                createdFolders.append(createdFolder)
                return .folder(createdFolder.id)
            } catch SourceManagementServiceError.duplicateFolderName {
                let refreshedCache = try OPMLImportFolderCache(
                    folders: sourceManagementService.fetchFolders()
                )
                folderCache = refreshedCache
                if let existingFolder = folderCache.folder(named: name) {
                    return .folder(existingFolder.id)
                }
                throw SourceManagementServiceError.duplicateFolderName(name)
            }
        }
    }

    private static func sourceManagementFeedPreview(
        from entry: OPMLImportPreviewEntryDTO
    ) -> SourceManagementFeedPreview {
        let feedURL = entry.normalizedFeedURL ?? entry.source.xmlURL
        return SourceManagementFeedPreview(
            requestedURL: feedURL,
            resolvedFeedURL: feedURL,
            title: entry.displayTitle,
            subtitle: nil,
            siteURL: normalizedSiteURL(entry.source.htmlURL),
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
    private var foldersByName: [String: SourceManagementFolderSummary]

    init(folders: [SourceManagementFolderSummary]) throws {
        foldersByName = [:]
        for folder in folders {
            foldersByName[Self.comparisonKey(folder.name)] = folder
        }
    }

    func folder(named name: String) -> SourceManagementFolderSummary? {
        foldersByName[Self.comparisonKey(name)]
    }

    mutating func insert(_ folder: SourceManagementFolderSummary) {
        foldersByName[Self.comparisonKey(folder.name)] = folder
    }

    private static func comparisonKey(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

private extension SourceManagementServiceError {
    var isImportSkipReason: Bool {
        switch self {
        case .duplicateFeed, .duplicateFeedDisplayName:
            return true
        default:
            return false
        }
    }
}
