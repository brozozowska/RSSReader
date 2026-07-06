import Foundation
import UIKit

@MainActor
protocol FeedIconDiscovering: Sendable {
    func discoverIconURL(
        feedURL: URL,
        siteURL: URL?,
        metadataIconURL: URL?
    ) async -> URL?
}

@MainActor
final class FeedIconDiscoveryService: FeedIconDiscovering {
    private let logger: Logging
    private let httpClient: any HTTPClient
    private let feedIconCache: any FeedIconCaching

    init(
        logger: Logging,
        httpClient: any HTTPClient,
        feedIconCache: any FeedIconCaching
    ) {
        self.logger = logger
        self.httpClient = httpClient
        self.feedIconCache = feedIconCache
    }

    func discoverIconURL(
        feedURL: URL,
        siteURL: URL?,
        metadataIconURL: URL?
    ) async -> URL? {
        let budget = FeedIconDiscoveryBudget(duration: Self.discoveryBudgetInterval)
        let originURL = siteURL
            .flatMap(FeedIconCandidateBuilder.originURL(for:))
            ?? FeedIconCandidateBuilder.originURL(for: feedURL)

        let metadataCandidates = metadataIconURL.map { [$0] } ?? []
        if let iconURL = await firstValidIconURL(in: metadataCandidates, budget: budget) {
            return iconURL
        }

        if let originURL,
           let iconURL = await firstValidIconURL(
            in: FeedIconCandidateBuilder.commonIconCandidates(for: originURL),
            budget: budget
           ) {
            return iconURL
        }

        guard let originURL,
              let htmlDocument = await fetchFeedHomeHTML(from: originURL, budget: budget) else {
            return nil
        }

        return await firstValidIconURL(
            in: FeedIconCandidateBuilder.htmlIconCandidates(
                in: htmlDocument.html,
                baseURL: htmlDocument.baseURL
            ),
            budget: budget
        )
    }

    private func firstValidIconURL(
        in iconURLs: [URL],
        budget: FeedIconDiscoveryBudget
    ) async -> URL? {
        for iconURL in iconURLs where FeedIconCandidateBuilder.isSupportedIconURL(iconURL) {
            guard budget.hasTimeRemaining else { return nil }

            do {
                guard try await loadValidatedRasterIconData(for: iconURL, budget: budget) != nil else {
                    continue
                }
                try Task.checkCancellation()

                return iconURL
            } catch is CancellationError {
                return nil
            } catch {
                logger.debug(
                    "Failed to discover feed icon at \(iconURL.absoluteString): \(String(describing: error))"
                )
            }
        }

        return nil
    }

    private func loadValidatedRasterIconData(
        for iconURL: URL,
        budget: FeedIconDiscoveryBudget
    ) async throws -> Data? {
        if let cachedData = try await feedIconCache.cachedImageData(for: iconURL) {
            return FeedIconImagePolicy.isSuitableRasterIcon(cachedData) ? cachedData : nil
        }
        guard let timeoutInterval = budget.requestTimeoutInterval(max: Self.requestTimeoutInterval) else {
            return nil
        }

        let response = try await httpClient.execute(
            HTTPRequest(
                url: iconURL,
                headers: [
                    "Accept": "image/png, image/jpeg, image/x-icon, image/*;q=0.9, */*;q=0.1",
                    "User-Agent": "RSSReader/0 (Feed Icon Discovery)"
                ],
                timeoutInterval: timeoutInterval
            )
        )
        guard (200...299).contains(response.statusCode),
              FeedIconImagePolicy.isSuitableRasterIcon(response.body) else {
            return nil
        }

        try await feedIconCache.storeImageData(response.body, for: iconURL)
        return response.body
    }

    private func fetchFeedHomeHTML(
        from url: URL,
        budget: FeedIconDiscoveryBudget
    ) async -> FeedIconHTMLDocument? {
        guard let timeoutInterval = budget.requestTimeoutInterval(max: Self.requestTimeoutInterval) else {
            return nil
        }

        do {
            let response = try await httpClient.execute(
                HTTPRequest(
                    url: url,
                    headers: [
                        "Accept": "text/html, application/xhtml+xml;q=0.9, */*;q=0.1",
                        "User-Agent": "RSSReader/0 (Feed Icon Discovery)"
                    ],
                    timeoutInterval: timeoutInterval
                )
            )
            guard (200...299).contains(response.statusCode),
                  let html = String(data: response.body, encoding: .utf8) else {
                return nil
            }
            return FeedIconHTMLDocument(html: html, baseURL: response.url)
        } catch {
            logger.debug(
                "Failed to load feed homepage for icon discovery from \(url.absoluteString): \(String(describing: error))"
            )
            return nil
        }
    }

    private static let discoveryBudgetInterval: TimeInterval = 4
    private static let requestTimeoutInterval: TimeInterval = 2
}

private struct FeedIconDiscoveryBudget {
    let deadline: Date

    init(duration: TimeInterval) {
        deadline = Date().addingTimeInterval(duration)
    }

    var hasTimeRemaining: Bool {
        remainingTimeInterval > 0
    }

    func requestTimeoutInterval(max maximumInterval: TimeInterval) -> TimeInterval? {
        let remaining = remainingTimeInterval
        guard remaining > 0 else { return nil }
        return min(maximumInterval, remaining)
    }

    private var remainingTimeInterval: TimeInterval {
        max(0, deadline.timeIntervalSinceNow)
    }
}

private struct FeedIconHTMLDocument {
    let html: String
    let baseURL: URL
}

enum FeedIconCandidateBuilder {
    static func originURL(for url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme != nil,
              components.host != nil else {
            return nil
        }

        components.path = "/"
        components.query = nil
        components.fragment = nil
        return components.url
    }

    static func commonIconCandidates(for url: URL) -> [URL] {
        guard let originURL = originURL(for: url) else { return [] }

        return deduplicated(
            [
                appendingIconPath("/apple-touch-icon.png", to: originURL),
                appendingIconPath("/apple-touch-icon-precomposed.png", to: originURL),
                appendingIconPath("/favicon-32x32.png", to: originURL),
                appendingIconPath("/favicon.png", to: originURL),
                appendingIconPath("/favicon.ico", to: originURL)
            ].compactMap { $0 }
        )
    }

    static func htmlIconCandidates(in html: String, baseURL: URL) -> [URL] {
        guard let linkTagExpression = try? NSRegularExpression(
            pattern: #"<link\b[^>]*>"#,
            options: [.caseInsensitive]
        ) else {
            return []
        }

        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
        let candidates = linkTagExpression.matches(in: html, range: nsRange).compactMap { match -> FeedIconCandidate? in
            guard let tagRange = Range(match.range, in: html) else { return nil }
            let attributes = linkTagAttributes(in: String(html[tagRange]))
            guard let href = attributes["href"],
                  let rel = attributes["rel"],
                  let priority = iconPriority(forRelValue: rel),
                  let url = URL(string: href, relativeTo: baseURL)?.absoluteURL,
                  isSupportedIconURL(url) else {
                return nil
            }

            return FeedIconCandidate(url: url, priority: priority)
        }

        return deduplicated(
            candidates
                .sorted { lhs, rhs in
                    lhs.priority == rhs.priority
                        ? lhs.url.absoluteString < rhs.url.absoluteString
                        : lhs.priority < rhs.priority
                }
                .map(\.url)
        )
    }

    static func isSupportedIconURL(_ url: URL) -> Bool {
        url.pathExtension.lowercased() != "svg"
    }

    private struct FeedIconCandidate {
        let url: URL
        let priority: Int
    }

    private static func iconPriority(forRelValue relValue: String) -> Int? {
        let tokens = Set(relValue.lowercased().split(whereSeparator: \.isWhitespace).map(String.init))

        if tokens.contains("apple-touch-icon") || tokens.contains("apple-touch-icon-precomposed") {
            return 0
        }

        if tokens.contains("icon") || tokens.contains("shortcut") && tokens.contains("icon") {
            return 1
        }

        return nil
    }

    private static func appendingIconPath(_ path: String, to originURL: URL) -> URL? {
        URL(string: path, relativeTo: originURL)?.absoluteURL
    }

    private static func deduplicated(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { url in
            seen.insert(url.absoluteString).inserted
        }
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
}

enum FeedIconImagePolicy {
    static func isSuitableRasterIcon(_ data: Data) -> Bool {
        guard let image = UIImage(data: data) else { return false }
        return isSuitableIconSize(image.size)
    }

    static func isSuitableIconSize(_ size: CGSize) -> Bool {
        guard size.width > 0, size.height > 0 else { return false }

        let aspectRatio = max(size.width, size.height) / min(size.width, size.height)
        return aspectRatio <= 2
    }
}
