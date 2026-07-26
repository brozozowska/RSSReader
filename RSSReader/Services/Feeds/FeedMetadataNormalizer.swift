import Foundation

nonisolated enum FeedMetadataNormalizer {
    static func normalize(_ metadata: ParsedFeedMetadataDTO, feedURL: String) -> ParsedFeedMetadataDTO {
        let normalizedSiteURL = FeedURLNormalizer.normalizeSourceURL(metadata.siteURL)
        let fallbackSiteURL = normalizedSiteURL ?? FeedURLNormalizer.makeOriginURL(from: feedURL)

        return ParsedFeedMetadataDTO(
            title: FeedTextHTMLNormalizer.normalizeTitle(metadata.title),
            subtitle: FeedTextHTMLNormalizer.normalizeTextBlock(metadata.subtitle),
            siteURL: normalizedSiteURL,
            iconURL: FeedIconURLPolicy.normalizeFeedIconURL(
                metadata.iconURL,
                siteURL: fallbackSiteURL,
                baseURL: normalizedSiteURL ?? fallbackSiteURL ?? feedURL
            ),
            language: FeedTextHTMLNormalizer.normalizeInlineText(metadata.language)
        )
    }
}
