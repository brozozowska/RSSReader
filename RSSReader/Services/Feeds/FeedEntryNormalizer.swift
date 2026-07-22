import Foundation

nonisolated enum FeedEntryNormalizer {
    static func normalize(_ entry: ParsedFeedEntryDTO, feedURL: String) -> ParsedFeedEntryDTO {
        let normalizedEntry = normalizeFields(entry)
        let publishedAt = parsePublishedAt(for: normalizedEntry)

        let externalID = ArticleIdentityService.makeExternalID(
            from: ArticleIdentityInput(
                feedURL: feedURL,
                guid: normalizedEntry.guid,
                canonicalURL: normalizedEntry.canonicalURL,
                articleURL: normalizedEntry.url,
                title: normalizedEntry.title ?? normalizedEntry.summary ?? "",
                publishedAt: publishedAt
            )
        )

        return ParsedFeedEntryDTO(
            externalID: externalID,
            guid: normalizedEntry.guid,
            url: normalizedEntry.url,
            canonicalURL: normalizedEntry.canonicalURL,
            title: normalizedEntry.title,
            summary: normalizedEntry.summary,
            contentHTML: normalizedEntry.contentHTML,
            contentText: normalizedEntry.contentText,
            author: normalizedEntry.author,
            publishedAtRaw: normalizedEntry.publishedAtRaw,
            updatedAtRaw: normalizedEntry.updatedAtRaw,
            imageURL: normalizedEntry.imageURL
        )
    }

    static func parsePublishedAt(for entry: ParsedFeedEntryDTO) -> Date? {
        FeedDateParsingService.parse(entry.publishedAtRaw)
    }

    static func parseUpdatedAt(for entry: ParsedFeedEntryDTO) -> Date? {
        FeedDateParsingService.parse(entry.updatedAtRaw)
    }

    private static func normalizeFields(_ entry: ParsedFeedEntryDTO) -> ParsedFeedEntryDTO {
        ParsedFeedEntryDTO(
            externalID: entry.externalID,
            guid: FeedTextHTMLNormalizer.normalizeScalar(entry.guid),
            url: FeedURLNormalizer.normalizeSourceURL(entry.url),
            canonicalURL: FeedURLNormalizer.normalizeSourceURL(entry.canonicalURL),
            title: FeedTextHTMLNormalizer.normalizeTitle(entry.title),
            summary: FeedTextHTMLNormalizer.normalizeTextBlock(entry.summary),
            contentHTML: FeedTextHTMLNormalizer.normalizeHTMLContent(entry.contentHTML),
            contentText: FeedTextHTMLNormalizer.normalizeTextContent(entry.contentText),
            author: FeedTextHTMLNormalizer.normalizeAuthor(entry.author),
            publishedAtRaw: FeedTextHTMLNormalizer.normalizeScalar(entry.publishedAtRaw),
            updatedAtRaw: FeedTextHTMLNormalizer.normalizeScalar(entry.updatedAtRaw),
            imageURL: FeedURLNormalizer.normalizeSourceURL(entry.imageURL)
        )
    }
}
