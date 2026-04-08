import Foundation

enum FeedNormalizationService {
    static func normalize(_ feed: ParsedFeedDTO, feedURL: String) -> ParsedFeedDTO {
        let normalizedFeedURL = normalizeSourceURL(feedURL) ?? feedURL

        return ParsedFeedDTO(
            kind: feed.kind,
            metadata: normalize(feed.metadata),
            entries: feed.entries.map { normalize($0, feedURL: normalizedFeedURL) }
        )
    }

    private static func normalize(_ metadata: ParsedFeedMetadataDTO) -> ParsedFeedMetadataDTO {
        let normalizedSiteURL = normalizeSourceURL(metadata.siteURL)

        return ParsedFeedMetadataDTO(
            title: normalizeTitle(metadata.title),
            subtitle: normalizeTextBlock(metadata.subtitle),
            siteURL: normalizedSiteURL,
            iconURL: normalizeFeedIconURL(metadata.iconURL, siteURL: normalizedSiteURL),
            language: normalizeInlineText(metadata.language)
        )
    }

    private static func normalize(_ entry: ParsedFeedEntryDTO) -> ParsedFeedEntryDTO {
        ParsedFeedEntryDTO(
            externalID: entry.externalID,
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

    static func normalize(_ entry: ParsedFeedEntryDTO, feedURL: String) -> ParsedFeedEntryDTO {
        let normalizedEntry = normalize(entry)
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

    private static func normalizeFeedIconURL(_ iconURL: String?, siteURL: String?) -> String? {
        guard let normalizedIconURL = normalizeSourceURL(iconURL) else {
            return makeSiteFaviconURL(from: siteURL)
        }
        guard shouldKeepFeedIconURL(normalizedIconURL) else {
            return makeSiteFaviconURL(from: siteURL) ?? normalizedIconURL
        }

        return normalizedIconURL
    }

    private static func shouldKeepFeedIconURL(_ value: String) -> Bool {
        guard let components = URLComponents(string: value) else { return true }

        let path = components.path.lowercased()
        let filename = URL(fileURLWithPath: path).lastPathComponent.lowercased()

        if filename.hasSuffix(".ico") || filename.contains("favicon") {
            return true
        }

        if filename.contains("apple-touch-icon") || filename.contains("mask-icon") {
            return true
        }

        if filename.contains("icon"), filename.containsAny(of: nonSquareIconTokens) == false {
            return true
        }

        if filename.containsSquareDimensionToken {
            return true
        }

        if filename.containsAny(of: nonSquareIconTokens) {
            return false
        }

        return true
    }

    private static func makeSiteFaviconURL(from siteURL: String?) -> String? {
        guard let siteURL,
              var components = URLComponents(string: siteURL),
              components.host != nil else {
            return nil
        }

        components.path = "/favicon.ico"
        components.query = nil
        components.fragment = nil
        return components.string
    }

    private static let nonSquareIconTokens = [
        "banner",
        "cover",
        "header",
        "hero",
        "landscape",
        "logo",
        "masthead",
        "wordmark"
    ]
}

private extension String {
    func containsAny(of tokens: [String]) -> Bool {
        tokens.contains { contains($0) }
    }

    var containsSquareDimensionToken: Bool {
        range(
            of: #"(?<!\d)(16|24|32|48|57|60|64|72|76|96|114|120|128|144|152|167|180|192|256|512)x\1(?!\d)"#,
            options: .regularExpression
        ) != nil
    }
}
