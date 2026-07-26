import Foundation

nonisolated enum FeedNormalizationService {
    static func normalize(_ feed: ParsedFeedDTO, feedURL: String) -> ParsedFeedDTO {
        normalize(
            feed,
            feedURL: feedURL,
            cancellationCheck: {},
            progressProbe: nil
        )
    }

    static func normalize(
        _ feed: ParsedFeedDTO,
        feedURL: String,
        cancellationCheck: FeedParsingCancellationCheck,
        progressProbe: FeedEntryLoopProgressProbe?
    ) rethrows -> ParsedFeedDTO {
        let normalizedFeedURL = FeedURLNormalizer.normalizeSourceURL(feedURL) ?? feedURL
        var normalizedEntries: [ParsedFeedEntryDTO] = []
        normalizedEntries.reserveCapacity(feed.entries.count)

        for (index, entry) in feed.entries.enumerated() {
            try FeedParsingCancellationPolicy.checkBeforeEntry(
                at: index,
                cancellationCheck: cancellationCheck
            )
            normalizedEntries.append(
                FeedEntryNormalizer.normalize(entry, feedURL: normalizedFeedURL)
            )
            progressProbe?(index + 1)
        }
        try cancellationCheck()

        return ParsedFeedDTO(
            kind: feed.kind,
            metadata: FeedMetadataNormalizer.normalize(feed.metadata, feedURL: normalizedFeedURL),
            entries: normalizedEntries
        )
    }

    static func normalize(_ entry: ParsedFeedEntryDTO, feedURL: String) -> ParsedFeedEntryDTO {
        FeedEntryNormalizer.normalize(entry, feedURL: feedURL)
    }
}
