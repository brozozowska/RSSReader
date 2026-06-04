import Foundation

enum FeedNormalizationService {
    static func normalize(_ feed: ParsedFeedDTO, feedURL: String) -> ParsedFeedDTO {
        let normalizedFeedURL = FeedURLNormalizer.normalizeSourceURL(feedURL) ?? feedURL

        return ParsedFeedDTO(
            kind: feed.kind,
            metadata: FeedMetadataNormalizer.normalize(feed.metadata, feedURL: normalizedFeedURL),
            entries: feed.entries.map { FeedEntryNormalizer.normalize($0, feedURL: normalizedFeedURL) }
        )
    }

    static func normalize(_ entry: ParsedFeedEntryDTO, feedURL: String) -> ParsedFeedEntryDTO {
        FeedEntryNormalizer.normalize(entry, feedURL: feedURL)
    }

    static func parsePublishedAt(for entry: ParsedFeedEntryDTO) -> Date? {
        FeedEntryNormalizer.parsePublishedAt(for: entry)
    }

    static func parseUpdatedAt(for entry: ParsedFeedEntryDTO) -> Date? {
        FeedEntryNormalizer.parseUpdatedAt(for: entry)
    }
}
