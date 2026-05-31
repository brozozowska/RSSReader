import Foundation

enum FeedNormalizationService {
    static func normalize(_ feed: ParsedFeedDTO, feedURL: String) -> ParsedFeedDTO {
        let normalizedFeedURL = normalizeSourceURL(feedURL) ?? feedURL

        return ParsedFeedDTO(
            kind: feed.kind,
            metadata: normalize(feed.metadata, feedURL: normalizedFeedURL),
            entries: feed.entries.map { normalize($0, feedURL: normalizedFeedURL) }
        )
    }

    private static func normalize(_ metadata: ParsedFeedMetadataDTO, feedURL: String) -> ParsedFeedMetadataDTO {
        let normalizedSiteURL = normalizeSourceURL(metadata.siteURL)
        let fallbackSiteURL = normalizedSiteURL ?? makeOriginURL(from: feedURL)

        return ParsedFeedMetadataDTO(
            title: normalizeTitle(metadata.title),
            subtitle: normalizeTextBlock(metadata.subtitle),
            siteURL: normalizedSiteURL,
            iconURL: normalizeFeedIconURL(
                metadata.iconURL,
                siteURL: fallbackSiteURL,
                baseURL: normalizedSiteURL ?? fallbackSiteURL ?? feedURL
            ),
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
            author: normalizeAuthor(entry.author),
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
        guard let value = normalizeScalar(value) else { return nil }

        let decodedValue = decodeHTMLEntities(in: value)
        let textValue = stripHTML(decodedValue)
        guard let value = normalizeInlineText(removeInvisibleCharacters(from: textValue)) else { return nil }

        let normalizedValue = value
            .replacingOccurrences(of: " ,", with: ",")
            .replacingOccurrences(of: " .", with: ".")
            .replacingOccurrences(of: " !", with: "!")
            .replacingOccurrences(of: " ?", with: "?")
            .replacingOccurrences(of: " :", with: ":")
            .replacingOccurrences(of: " ;", with: ";")

        return normalizedValue.isEmpty ? nil : normalizedValue
    }

    private static func decodeHTMLEntities(in value: String) -> String {
        var decodedValue = value

        for _ in 0..<3 {
            let nextValue = decodeHTMLEntitiesOnce(in: decodedValue)
            guard nextValue != decodedValue else { break }
            decodedValue = nextValue
        }

        return decodedValue
    }

    private static func decodeHTMLEntitiesOnce(in value: String) -> String {
        var decodedValue = ""
        var currentIndex = value.startIndex

        while currentIndex < value.endIndex {
            guard value[currentIndex] == "&",
                  let semicolonIndex = value[currentIndex...].firstIndex(of: ";")
            else {
                decodedValue.append(value[currentIndex])
                currentIndex = value.index(after: currentIndex)
                continue
            }

            let entityStartIndex = value.index(after: currentIndex)
            let entity = String(value[entityStartIndex..<semicolonIndex])

            if let decodedEntity = decodeEntity(entity) {
                decodedValue.append(decodedEntity)
                currentIndex = value.index(after: semicolonIndex)
            } else {
                decodedValue.append(value[currentIndex])
                currentIndex = value.index(after: currentIndex)
            }
        }

        return decodedValue
    }

    private static func decodeEntity(_ entity: String) -> String? {
        if entity.hasPrefix("#x") || entity.hasPrefix("#X") {
            return decodeNumericEntity(String(entity.dropFirst(2)), radix: 16)
        }

        if entity.hasPrefix("#") {
            return decodeNumericEntity(String(entity.dropFirst()), radix: 10)
        }

        return namedHTMLEntities[entity.lowercased()]
    }

    private static func decodeNumericEntity(_ value: String, radix: Int) -> String? {
        guard let scalarValue = UInt32(value, radix: radix) else {
            return nil
        }

        if let legacyCharacter = legacyC1HTMLEntities[scalarValue] {
            return legacyCharacter
        }

        guard let scalar = UnicodeScalar(scalarValue) else {
            return nil
        }

        return String(Character(scalar))
    }

    private static func stripHTML(_ value: String) -> String {
        value
            .replacingOccurrences(
                of: #"<[^>]+>"#,
                with: " ",
                options: [.regularExpression, .caseInsensitive]
            )
    }

    private static func removeInvisibleCharacters(from value: String) -> String {
        var normalizedValue = ""

        for scalar in value.unicodeScalars {
            if scalar.value == 0x00A0 {
                normalizedValue.append(" ")
                continue
            }

            switch scalar.properties.generalCategory {
            case .control, .format, .surrogate, .privateUse, .unassigned:
                continue
            default:
                normalizedValue.unicodeScalars.append(scalar)
            }
        }

        return normalizedValue
    }

    private static let namedHTMLEntities: [String: String] = [
        "amp": "&",
        "apos": "'",
        "bull": "•",
        "copy": "©",
        "gt": ">",
        "hellip": "...",
        "laquo": "«",
        "lt": "<",
        "mdash": "—",
        "ndash": "–",
        "nbsp": " ",
        "quot": "\"",
        "raquo": "»",
        "reg": "®",
        "rsquo": "’",
        "trade": "™"
    ]

    private static let legacyC1HTMLEntities: [UInt32: String] = [
        128: "€",
        130: "‚",
        131: "ƒ",
        132: "„",
        133: "...",
        134: "†",
        135: "‡",
        136: "ˆ",
        137: "‰",
        138: "Š",
        139: "‹",
        140: "Œ",
        142: "Ž",
        145: "‘",
        146: "’",
        147: "“",
        148: "”",
        149: "•",
        150: "–",
        151: "—",
        152: "˜",
        153: "™",
        154: "š",
        155: "›",
        156: "œ",
        158: "ž",
        159: "Ÿ"
    ]

    private static func normalizeAuthor(_ value: String?) -> String? {
        guard let value = normalizeInlineText(value) else { return nil }

        let authorWithoutWrappedEmail = value.replacingOccurrences(
            of: #"\s*[\(<\[]\s*(?:mailto:)?[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\s*[\)>\]]\s*"#,
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )
        let authorWithoutEmail = authorWithoutWrappedEmail.replacingOccurrences(
            of: #"\b(?:mailto:)?[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#,
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )

        return normalizeInlineText(authorWithoutEmail)
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
        normalizeSourceURL(value, baseURL: nil)
    }

    private static func normalizeSourceURL(_ value: String?, baseURL: String?) -> String? {
        guard let value = normalizeScalar(value) else { return nil }

        let resolvedValue: String
        if let baseURL,
           hasAbsoluteWebURL(value) == false,
           let base = URL(string: baseURL),
           let resolvedURL = URL(string: value, relativeTo: base)?.absoluteURL {
            resolvedValue = resolvedURL.absoluteString
        } else {
            resolvedValue = value
        }

        guard let components = URLComponents(string: resolvedValue) else {
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
            ?? normalizeInlineText(resolvedValue)
    }

    private static func normalizeFeedIconURL(
        _ iconURL: String?,
        siteURL: String?,
        baseURL: String?
    ) -> String? {
        guard let normalizedIconURL = normalizeSourceURL(iconURL, baseURL: baseURL),
              hasAbsoluteWebURL(normalizedIconURL) else {
            return makeSiteFaviconURL(from: siteURL)
        }
        guard shouldKeepFeedIconURL(normalizedIconURL) else {
            return makeSiteFaviconURL(from: siteURL) ?? normalizedIconURL
        }

        return normalizedIconURL
    }

    private static func hasAbsoluteWebURL(_ value: String) -> Bool {
        guard let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              let host = components.host,
              host.isEmpty == false else {
            return false
        }

        return scheme == "http" || scheme == "https"
    }

    private static func makeOriginURL(from sourceURL: String?) -> String? {
        guard let sourceURL,
              var components = URLComponents(string: sourceURL),
              components.scheme != nil,
              components.host != nil else {
            return nil
        }

        components.path = "/"
        components.query = nil
        components.fragment = nil
        return components.string
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
