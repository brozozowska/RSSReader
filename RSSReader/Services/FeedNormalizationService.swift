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
            title: normalizeTitle(metadata.title),
            subtitle: normalizeTextBlock(metadata.subtitle),
            siteURL: normalizeSourceURL(metadata.siteURL),
            iconURL: normalizeSourceURL(metadata.iconURL),
            language: normalizeInlineText(metadata.language)
        )
    }

    static func normalize(_ entry: ParsedFeedEntryDTO) -> ParsedFeedEntryDTO {
        ParsedFeedEntryDTO(
            guid: normalizeScalar(entry.guid),
            url: normalizeSourceURL(entry.url),
            canonicalURL: normalizeSourceURL(entry.canonicalURL),
            title: normalizeTitle(entry.title),
            summary: normalizeTextBlock(entry.summary),
            contentHTML: normalizeHTMLContent(entry.contentHTML),
            contentText: normalizeTextContent(entry.contentText),
            author: normalizeInlineText(entry.author),
            publishedAtRaw: normalizeScalar(entry.publishedAtRaw),
            updatedAtRaw: normalizeScalar(entry.updatedAtRaw),
            imageURL: normalizeSourceURL(entry.imageURL)
        )
    }

    static func parsePublishedAt(for entry: ParsedFeedEntryDTO) -> Date? {
        FeedDateParsingService.parse(entry.publishedAtRaw)
    }

    static func parseUpdatedAt(for entry: ParsedFeedEntryDTO) -> Date? {
        FeedDateParsingService.parse(entry.updatedAtRaw)
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

    private static func normalizeTitle(_ value: String?) -> String? {
        guard let value = normalizeInlineText(value) else { return nil }

        let normalizedValue = value
            .replacingOccurrences(of: " ,", with: ",")
            .replacingOccurrences(of: " .", with: ".")
            .replacingOccurrences(of: " !", with: "!")
            .replacingOccurrences(of: " ?", with: "?")
            .replacingOccurrences(of: " :", with: ":")
            .replacingOccurrences(of: " ;", with: ";")

        return normalizedValue.isEmpty ? nil : normalizedValue
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

    private static func normalizeTextContent(_ value: String?) -> String? {
        normalizeTextBlock(value)?
            .replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    private static func normalizeHTMLContent(_ value: String?) -> String? {
        guard let value = normalizeScalar(value) else { return nil }

        let normalizedValue = value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return normalizedValue.isEmpty ? nil : normalizedValue
    }

    private static func normalizeSourceURL(_ value: String?) -> String? {
        guard let value = normalizeScalar(value) else { return nil }
        guard let components = URLComponents(string: value) else {
            return normalizeInlineText(value)
        }

        var normalizedComponents = components
        normalizedComponents.scheme = components.scheme?.lowercased()
        normalizedComponents.host = components.host?.lowercased()
        normalizedComponents.fragment = nil

        if let port = normalizedComponents.port {
            let isDefaultHTTPPort = normalizedComponents.scheme == "http" && port == 80
            let isDefaultHTTPSPort = normalizedComponents.scheme == "https" && port == 443

            if isDefaultHTTPPort || isDefaultHTTPSPort {
                normalizedComponents.port = nil
            }
        }

        if normalizedComponents.path.isEmpty {
            normalizedComponents.path = "/"
        }

        return normalizedComponents.string?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? normalizeInlineText(value)
    }
}
