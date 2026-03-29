import Foundation
import CryptoKit

struct ArticleIdentityInput: Sendable {
    let feedURL: String
    let guid: String?
    let canonicalURL: String?
    let articleURL: String?
    let title: String
    let publishedAt: Date?

    init(
        feedURL: String,
        guid: String? = nil,
        canonicalURL: String? = nil,
        articleURL: String? = nil,
        title: String,
        publishedAt: Date? = nil
    ) {
        self.feedURL = feedURL
        self.guid = guid
        self.canonicalURL = canonicalURL
        self.articleURL = articleURL
        self.title = title
        self.publishedAt = publishedAt
    }
}

enum ArticleIdentityService {
    static func makeExternalID(from input: ArticleIdentityInput) -> String {
        let normalizedFeedURL = normalizeRequiredURL(input.feedURL)

        if let guid = normalizeText(input.guid), guid.isEmpty == false {
            return "guid|\(normalizedFeedURL)|\(guid)"
        }

        if let canonicalURL = normalizeURL(input.canonicalURL), canonicalURL.isEmpty == false {
            return "canonical-url|\(normalizedFeedURL)|\(canonicalURL)"
        }

        if let articleURL = normalizeURL(input.articleURL), articleURL.isEmpty == false {
            return "article-url|\(normalizedFeedURL)|\(articleURL)"
        }

        let normalizedTitle = normalizeTitle(input.title)
        let normalizedPublishedAt = normalizeDate(input.publishedAt)
        let fallbackPayload = [
            normalizedFeedURL,
            normalizedTitle,
            normalizedPublishedAt
        ].joined(separator: "|")

        return "fallback|\(sha256(fallbackPayload))"
    }

    private static func normalizeText(_ value: String?) -> String? {
        guard let value else { return nil }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }
        return trimmed
    }

    private static func normalizeTitle(_ value: String) -> String {
        normalizeWhitespace(value).lowercased()
    }

    private static func normalizeRequiredURL(_ value: String) -> String {
        normalizeURL(value) ?? normalizeWhitespace(value).lowercased()
    }

    private static func normalizeURL(_ value: String?) -> String? {
        guard let value = normalizeText(value) else { return nil }
        guard let components = URLComponents(string: value) else {
            return normalizeWhitespace(value).lowercased()
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

        return normalizedComponents.string?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            ?? normalizeWhitespace(value).lowercased()
    }

    private static func normalizeWhitespace(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.isEmpty == false }
            .joined(separator: " ")
    }

    private static func normalizeDate(_ value: Date?) -> String {
        guard let value else { return "no-date" }
        return publishedAtFormatter.string(from: value)
    }

    private static func sha256(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static let publishedAtFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
