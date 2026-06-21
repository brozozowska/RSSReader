import Foundation

enum FeedManagementFeedDiscoveryPlanner {
    static func makePlan(for input: String) throws -> FeedManagementFeedDiscoveryPlan {
        let normalizedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedInput.isEmpty == false else {
            throw FeedManagementServiceError.invalidFeedURL(input)
        }

        let inputURLs = try normalizedInputURLs(from: normalizedInput, originalInput: input)
        var feedURLs: [URL] = []
        var siteURLs: [URL] = []
        var fallbackFeedURLs: [URL] = []

        for inputURL in inputURLs {
            siteURLs.append(inputURL)

            guard let originURL = originURL(for: inputURL) else { continue }
            siteURLs.append(originURL)

            if isBareSiteURL(inputURL) {
                for path in commonFeedPaths {
                    if let feedURL = URL(string: path, relativeTo: originURL)?.absoluteURL {
                        feedURLs.append(feedURL)
                    }
                }
                fallbackFeedURLs.append(inputURL)
            } else {
                feedURLs.append(inputURL)
            }
        }

        let deduplicatedFeedURLs = deduplicate(feedURLs)
        let deduplicatedFallbackFeedURLs = deduplicate(fallbackFeedURLs)
        return FeedManagementFeedDiscoveryPlan(
            displayURL: inputURLs[0].absoluteString,
            feedURLs: deduplicatedFeedURLs,
            siteURLs: deduplicate(siteURLs),
            fallbackFeedURLs: deduplicatedFallbackFeedURLs
        )
    }

    static func displayURLString(for input: String) -> String? {
        try? makePlan(for: input).displayURL
    }

    static func autodiscoveredFeedURLs(in html: String, baseURL: URL) -> [URL] {
        guard let linkTagExpression = try? NSRegularExpression(
            pattern: #"<link\b[^>]*>"#,
            options: [.caseInsensitive]
        ) else {
            return []
        }

        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
        let urls = linkTagExpression.matches(in: html, range: nsRange).compactMap { match -> URL? in
            guard let tagRange = Range(match.range, in: html) else { return nil }
            let attributes = linkTagAttributes(in: String(html[tagRange]))
            guard let href = attributes["href"],
                  let rel = attributes["rel"]?.lowercased(),
                  rel.split(whereSeparator: \.isWhitespace).contains("alternate"),
                  isSupportedFeedLinkType(attributes["type"]) else {
                return nil
            }

            return URL(string: href, relativeTo: baseURL)?.absoluteURL
        }

        return deduplicate(urls)
    }

    private static let commonFeedPaths = [
        "/feed",
        "/rss",
        "/rss.xml",
        "/feed.xml",
        "/atom.xml"
    ]

    private static func normalizedInputURLs(
        from normalizedInput: String,
        originalInput: String
    ) throws -> [URL] {
        if let explicitURL = URL(string: normalizedInput),
           let scheme = explicitURL.scheme?.lowercased(),
           scheme.isEmpty == false {
            guard ["http", "https"].contains(scheme),
                  explicitURL.host?.isEmpty == false else {
                throw FeedManagementServiceError.invalidFeedURL(originalInput)
            }
            return [explicitURL]
        }

        let candidateStrings = [
            "https://\(normalizedInput)",
            "http://\(normalizedInput)"
        ]

        let urls = candidateStrings.compactMap { candidate in
            URL(string: candidate)
        }
        .filter { url in
            guard let scheme = url.scheme?.lowercased(),
                  ["http", "https"].contains(scheme),
                  url.host?.isEmpty == false else {
                return false
            }
            return true
        }

        guard urls.isEmpty == false else {
            throw FeedManagementServiceError.invalidFeedURL(originalInput)
        }

        return urls
    }

    private static func originURL(for url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.isEmpty == false,
              components.host?.isEmpty == false else {
            return nil
        }

        components.path = "/"
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private static func isBareSiteURL(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }

        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return path.isEmpty && components.query == nil && components.fragment == nil
    }

    private static func linkTagAttributes(in tag: String) -> [String: String] {
        guard let attributeExpression = try? NSRegularExpression(
            pattern: #"([A-Za-z_:][-A-Za-z0-9_:.]*)\s*=\s*("[^"]*"|'[^']*'|[^\s"'>]+)"#,
            options: [.caseInsensitive]
        ) else {
            return [:]
        }

        let nsRange = NSRange(tag.startIndex..<tag.endIndex, in: tag)
        return attributeExpression.matches(in: tag, range: nsRange).reduce(into: [String: String]()) { result, match in
            guard match.numberOfRanges == 3,
                  let nameRange = Range(match.range(at: 1), in: tag),
                  let valueRange = Range(match.range(at: 2), in: tag) else {
                return
            }

            let name = String(tag[nameRange]).lowercased()
            let rawValue = String(tag[valueRange])
            result[name] = unquotedAttributeValue(rawValue)
        }
    }

    private static func unquotedAttributeValue(_ value: String) -> String {
        guard value.count >= 2,
              let first = value.first,
              let last = value.last,
              (first == "\"" && last == "\"") || (first == "'" && last == "'") else {
            return value
        }

        return String(value.dropFirst().dropLast())
    }

    private static func isSupportedFeedLinkType(_ value: String?) -> Bool {
        guard let value else { return false }
        let normalizedValue = value
            .split(separator: ";", maxSplits: 1)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch normalizedValue {
        case "application/rss+xml",
                "application/atom+xml",
                "application/rdf+xml",
                "application/xml",
                "text/xml":
            return true
        default:
            return normalizedValue?.hasSuffix("+xml") == true
        }
    }

    private static func deduplicate(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { url in
            seen.insert(url.absoluteString).inserted
        }
    }
}
