import Foundation

@MainActor
struct FeedManagementNormalizationPolicy {
    let logger: Logging
    let feedRepository: any FeedRepository
    let folderRepository: any FolderRepository

    func normalizedFeedURLString(_ value: String) throws -> String {
        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedValue.isEmpty == false else {
            throw FeedManagementServiceError.invalidFeedURL(value)
        }
        return normalizedValue
    }

    func normalizedFolderName(_ value: String) throws -> String {
        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedValue.isEmpty == false else {
            throw FeedManagementServiceError.emptyFolderName
        }
        return normalizedValue
    }

    func normalizedNonEmptyString(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedValue.isEmpty ? nil : normalizedValue
    }

    func normalizedDisplayTitle(_ value: String?) -> String? {
        normalizedNonEmptyString(value)
    }

    func ensureUniqueFeedDisplayTitle(_ title: String, excluding feedID: UUID? = nil) throws {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedTitle.isEmpty == false else { return }

        let duplicate = try feedRepository.fetchAllFeeds().first { feed in
            if let feedID, feed.id == feedID {
                return false
            }

            return feed.displayTitle
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .compare(normalizedTitle, options: [.caseInsensitive]) == .orderedSame
        }

        if duplicate != nil {
            logger.error("Skipped feed save because another feed already uses display name: \(normalizedTitle)")
            throw FeedManagementServiceError.duplicateFeedDisplayName(normalizedTitle)
        }
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

    func resolveFolder(for placement: FeedManagementFolderPlacement) throws -> Folder? {
        switch placement {
        case .ungrouped:
            return nil
        case .folder(let folderID):
            guard let folder = try folderRepository.fetchFolder(id: folderID) else {
                logger.error("Skipped feed management operation because folder was not found: \(folderID.uuidString)")
                throw FeedManagementServiceError.folderNotFound(folderID)
            }
            return folder
        }
    }

    func requireFeedSummary(
        _ feed: Feed?,
        feedID: UUID,
        operation: String
    ) throws -> Feed {
        guard let feed else {
            logger.error("Skipped feed \(operation) because feed update path returned no feed: \(feedID.uuidString)")
            throw FeedManagementServiceError.feedNotFound(feedID)
        }
        return feed
    }
}
