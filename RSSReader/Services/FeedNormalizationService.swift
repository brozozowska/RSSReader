import Foundation

enum FeedNormalizationService {
    static func normalize(_ feed: ParsedFeedDTO) -> ParsedFeedDTO {
        ParsedFeedDTO(
            kind: feed.kind,
            metadata: normalize(feed.metadata),
            entries: feed.entries.map { normalize($0) }
        )
    }

    static func normalize(_ metadata: ParsedFeedMetadataDTO) -> ParsedFeedMetadataDTO {
        ParsedFeedMetadataDTO(
            title: normalizeInlineText(metadata.title),
            subtitle: normalizeTextBlock(metadata.subtitle),
            siteURL: normalizeScalar(metadata.siteURL),
            iconURL: normalizeScalar(metadata.iconURL),
            language: normalizeInlineText(metadata.language)
        )
    }

    static func normalize(_ entry: ParsedFeedEntryDTO) -> ParsedFeedEntryDTO {
        ParsedFeedEntryDTO(
            guid: normalizeScalar(entry.guid),
            url: normalizeScalar(entry.url),
            canonicalURL: normalizeScalar(entry.canonicalURL),
            title: normalizeInlineText(entry.title),
            summary: normalizeTextBlock(entry.summary),
            contentHTML: normalizeTextBlock(entry.contentHTML),
            contentText: normalizeTextBlock(entry.contentText),
            author: normalizeInlineText(entry.author),
            publishedAtRaw: normalizeScalar(entry.publishedAtRaw),
            updatedAtRaw: normalizeScalar(entry.updatedAtRaw),
            imageURL: normalizeScalar(entry.imageURL)
        )
    }

    private static func normalizeScalar(_ value: String?) -> String? {
        guard let value else { return nil }

        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedValue.isEmpty == false else { return nil }
        return normalizedValue
    }

    private static func normalizeInlineText(_ value: String?) -> String? {
        guard let value = normalizeScalar(value) else { return nil }

        let collapsedValue = value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.isEmpty == false }
            .joined(separator: " ")

        return collapsedValue.isEmpty ? nil : collapsedValue
    }

    private static func normalizeTextBlock(_ value: String?) -> String? {
        guard let value = normalizeScalar(value) else { return nil }

        let lines = value
            .components(separatedBy: .newlines)
            .map { line in
                line
                    .components(separatedBy: .whitespaces)
                    .filter { $0.isEmpty == false }
                    .joined(separator: " ")
            }

        let normalizedValue = lines
            .drop(while: { $0.isEmpty })
            .reversed()
            .drop(while: { $0.isEmpty })
            .reversed()
            .joined(separator: "\n")

        return normalizedValue.isEmpty ? nil : normalizedValue
    }
}
