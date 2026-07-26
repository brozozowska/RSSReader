import Foundation

nonisolated enum FeedIconURLPolicy {
    static func normalizeFeedIconURL(
        _ iconURL: String?,
        siteURL: String?,
        baseURL: String?
    ) -> String? {
        guard let normalizedIconURL = FeedURLNormalizer.normalizeSourceURL(iconURL, baseURL: baseURL),
              FeedURLNormalizer.hasAbsoluteWebURL(normalizedIconURL) else {
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
        "masthead",
        "wordmark"
    ]
}

private extension String {
    nonisolated func containsAny(of tokens: [String]) -> Bool {
        tokens.contains { contains($0) }
    }

    nonisolated var containsSquareDimensionToken: Bool {
        range(
            of: #"(?<!\d)(16|24|32|48|57|60|64|72|76|96|114|120|128|144|152|167|180|192|256|512)x\1(?!\d)"#,
            options: .regularExpression
        ) != nil
    }
}
