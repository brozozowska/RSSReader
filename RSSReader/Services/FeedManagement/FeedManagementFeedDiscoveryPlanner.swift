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
        let budget = AppComposition.resourceBudgetContract.discoveryHTML
        let urls = HTMLLinkDiscoveryParser.linkTagAttributes(
            in: html,
            maximumLinkTagCount: budget.maximumLinkTagCountToInspect
        ).compactMap { attributes -> URL? in
            guard let href = attributes["href"],
                  let rel = attributes["rel"]?.lowercased(),
                  rel.split(whereSeparator: \.isWhitespace).contains("alternate"),
                  isSupportedFeedLinkType(attributes["type"]) else {
                return nil
            }

            return URL(string: href, relativeTo: baseURL)?.absoluteURL
        }

        return Array(deduplicate(urls).prefix(budget.maximumDiscoveryCandidateCount))
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
