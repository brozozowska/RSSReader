import Foundation

struct OPMLImportPreviewPlan: Equatable, Sendable {
    let entries: [OPMLImportPreviewEntryDTO]
    let ignoredOutlineCount: Int

    var importableEntries: [OPMLImportPreviewEntryDTO] {
        entries.filter(\.isImportable)
    }

    var invalidEntryCount: Int {
        entries.filter { $0.isImportable == false }.count
    }
}

struct OPMLImportPreviewEntryDTO: Identifiable, Equatable, Sendable {
    let id: Int
    let source: OPMLFeedOutlineDTO
    let normalizedFeedURL: String?
    let displayTitle: String
    let normalizedFolderName: String?
    let folderResolution: OPMLImportFolderResolution
    let issues: [OPMLImportPreviewIssue]

    var isImportable: Bool {
        issues.isEmpty
    }
}

enum OPMLImportFolderResolution: Equatable, Sendable {
    case ungrouped
    case existingFolder(id: UUID, name: String)
    case newFolder(name: String)
}

enum OPMLImportPreviewIssue: Equatable, Sendable {
    case invalidFeedURL(String)
    case duplicateFeedURL(String, source: OPMLImportDuplicateSource)
    case duplicateDisplayTitle(String, source: OPMLImportDuplicateSource)
}

enum OPMLImportDuplicateSource: Equatable, Sendable {
    case existingFeed(id: UUID)
    case importedEntry(index: Int)
}

enum OPMLImportPreviewPlanner {
    @MainActor
    static func makePlan(
        document: OPMLDocumentDTO,
        sourceManagementService: any SourceManagementService
    ) throws -> OPMLImportPreviewPlan {
        try makePlan(
            document: document,
            existingFeeds: sourceManagementService.fetchFeeds(),
            existingFolders: sourceManagementService.fetchFolders()
        )
    }

    static func makePlan(
        document: OPMLDocumentDTO,
        existingFeeds: [SourceManagementFeedSummary],
        existingFolders: [SourceManagementFolderSummary]
    ) -> OPMLImportPreviewPlan {
        let context = OPMLImportPreviewContext(
            existingFeeds: existingFeeds,
            existingFolders: existingFolders
        )
        var importedFeedURLs: [String: Int] = [:]
        var importedDisplayTitles: [String: Int] = [:]

        let entries = document.feeds.enumerated().map { index, feed in
            makeEntry(
                id: index,
                feed: feed,
                context: context,
                importedFeedURLs: &importedFeedURLs,
                importedDisplayTitles: &importedDisplayTitles
            )
        }

        return OPMLImportPreviewPlan(
            entries: entries,
            ignoredOutlineCount: document.ignoredOutlineCount
        )
    }

    private static func makeEntry(
        id: Int,
        feed: OPMLFeedOutlineDTO,
        context: OPMLImportPreviewContext,
        importedFeedURLs: inout [String: Int],
        importedDisplayTitles: inout [String: Int]
    ) -> OPMLImportPreviewEntryDTO {
        let normalizedFeedURL = normalizedFeedURL(feed.xmlURL)
        let displayTitle = normalizedDisplayTitle(feed.displayTitle) ?? normalizedFeedURL ?? feed.xmlURL
        let normalizedFolderName = flattenedFolderName(feed.folderPath)
        var issues: [OPMLImportPreviewIssue] = []

        if let normalizedFeedURL {
            let feedURLKey = comparisonKey(normalizedFeedURL)
            if let existingFeedID = context.existingFeedIDsByURL[feedURLKey] {
                issues.append(.duplicateFeedURL(normalizedFeedURL, source: .existingFeed(id: existingFeedID)))
            } else if let importedEntryIndex = importedFeedURLs[feedURLKey] {
                issues.append(.duplicateFeedURL(normalizedFeedURL, source: .importedEntry(index: importedEntryIndex)))
            } else {
                importedFeedURLs[feedURLKey] = id
            }
        } else {
            issues.append(.invalidFeedURL(feed.xmlURL))
        }

        let displayTitleKey = comparisonKey(displayTitle)
        if let existingFeedID = context.existingFeedIDsByDisplayTitle[displayTitleKey] {
            issues.append(.duplicateDisplayTitle(displayTitle, source: .existingFeed(id: existingFeedID)))
        } else if let importedEntryIndex = importedDisplayTitles[displayTitleKey] {
            issues.append(.duplicateDisplayTitle(displayTitle, source: .importedEntry(index: importedEntryIndex)))
        } else {
            importedDisplayTitles[displayTitleKey] = id
        }

        return OPMLImportPreviewEntryDTO(
            id: id,
            source: feed,
            normalizedFeedURL: normalizedFeedURL,
            displayTitle: displayTitle,
            normalizedFolderName: normalizedFolderName,
            folderResolution: folderResolution(for: normalizedFolderName, context: context),
            issues: issues
        )
    }

    fileprivate static func normalizedFeedURL(_ value: String) -> String? {
        guard let normalizedURL = FeedURLNormalizer.normalizeSourceURL(value),
              FeedURLNormalizer.hasAbsoluteWebURL(normalizedURL) else {
            return nil
        }

        return normalizedURL
    }

    private static func normalizedDisplayTitle(_ value: String?) -> String? {
        normalizedNonEmptyString(value)
    }

    private static func flattenedFolderName(_ path: [String]) -> String? {
        let components = path.compactMap { normalizedNonEmptyString($0) }
        guard components.isEmpty == false else { return nil }
        return components.joined(separator: " / ")
    }

    private static func normalizedNonEmptyString(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedValue.isEmpty ? nil : normalizedValue
    }

    private static func folderResolution(
        for folderName: String?,
        context: OPMLImportPreviewContext
    ) -> OPMLImportFolderResolution {
        guard let folderName else { return .ungrouped }
        if let existingFolder = context.existingFoldersByName[comparisonKey(folderName)] {
            return .existingFolder(id: existingFolder.id, name: existingFolder.name)
        }
        return .newFolder(name: folderName)
    }

    fileprivate static func comparisonKey(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

private struct OPMLImportPreviewContext {
    let existingFeedIDsByURL: [String: UUID]
    let existingFeedIDsByDisplayTitle: [String: UUID]
    let existingFoldersByName: [String: SourceManagementFolderSummary]

    init(
        existingFeeds: [SourceManagementFeedSummary],
        existingFolders: [SourceManagementFolderSummary]
    ) {
        var feedIDsByURL: [String: UUID] = [:]
        var feedIDsByDisplayTitle: [String: UUID] = [:]
        var foldersByName: [String: SourceManagementFolderSummary] = [:]

        for feed in existingFeeds {
            if let normalizedURL = OPMLImportPreviewPlanner.normalizedFeedURL(feed.url) {
                let feedURLKey = OPMLImportPreviewPlanner.comparisonKey(normalizedURL)
                if feedIDsByURL[feedURLKey] == nil {
                    feedIDsByURL[feedURLKey] = feed.id
                }
            }

            let displayTitleKey = OPMLImportPreviewPlanner.comparisonKey(feed.title)
            if feedIDsByDisplayTitle[displayTitleKey] == nil {
                feedIDsByDisplayTitle[displayTitleKey] = feed.id
            }
        }

        for folder in existingFolders {
            let folderNameKey = OPMLImportPreviewPlanner.comparisonKey(folder.name)
            if foldersByName[folderNameKey] == nil {
                foldersByName[folderNameKey] = folder
            }
        }

        existingFeedIDsByURL = feedIDsByURL
        existingFeedIDsByDisplayTitle = feedIDsByDisplayTitle
        existingFoldersByName = foldersByName
    }
}
