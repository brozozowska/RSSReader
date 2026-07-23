import Foundation
import ImageIO
import UIKit

@MainActor
protocol FeedIconDiscovering: Sendable {
    func discoverIconURL(
        feedURL: URL,
        siteURL: URL?,
        metadataIconURL: URL?
    ) async throws -> URL?
}

@MainActor
final class FeedIconDiscoveryService: FeedIconDiscovering {
    private let logger: Logging
    private let httpClient: any HTTPClient
    private let feedIconCache: any FeedIconCaching
    private let discoveryBudgetInterval: TimeInterval
    private let requestTimeoutInterval: TimeInterval

    init(
        logger: Logging,
        httpClient: any HTTPClient,
        feedIconCache: any FeedIconCaching,
        discoveryBudgetInterval: TimeInterval = 4,
        requestTimeoutInterval: TimeInterval = 2
    ) {
        self.logger = logger
        self.httpClient = httpClient
        self.feedIconCache = feedIconCache
        self.discoveryBudgetInterval = discoveryBudgetInterval
        self.requestTimeoutInterval = requestTimeoutInterval
    }

    func discoverIconURL(
        feedURL: URL,
        siteURL: URL?,
        metadataIconURL: URL?
    ) async throws -> URL? {
        try Task.checkCancellation()
        let budget = FeedIconDiscoveryBudget(duration: discoveryBudgetInterval)
        let originURL = siteURL
            .flatMap(FeedIconCandidateBuilder.originURL(for:))
            ?? FeedIconCandidateBuilder.originURL(for: feedURL)

        let metadataCandidates = metadataIconURL.map { [$0] } ?? []
        if let iconURL = try await firstValidIconURL(in: metadataCandidates, budget: budget) {
            return iconURL
        }

        if let originURL,
           let iconURL = try await firstValidIconURL(
            in: FeedIconCandidateBuilder.commonIconCandidates(for: originURL),
            budget: budget
           ) {
            return iconURL
        }

        guard let originURL,
              let htmlDocument = try await fetchFeedHomeHTML(from: originURL, budget: budget) else {
            return nil
        }

        return try await firstValidIconURL(
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
    ) async throws -> URL? {
        for iconURL in iconURLs where FeedIconCandidateBuilder.isSupportedIconURL(iconURL) {
            try Task.checkCancellation()
            guard budget.hasTimeRemaining else { return nil }

            do {
                guard try await loadValidatedRasterIconData(for: iconURL, budget: budget) != nil else {
                    continue
                }
                try Task.checkCancellation()

                return iconURL
            } catch let error as CancellationError {
                throw error
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
        try Task.checkCancellation()
        if let cachedData = try await feedIconCache.cachedImageData(for: iconURL) {
            try Task.checkCancellation()
            return FeedIconImagePolicy.isSuitableRasterIcon(cachedData) ? cachedData : nil
        }
        guard let timeoutInterval = budget.requestTimeoutInterval(max: requestTimeoutInterval) else {
            return nil
        }

        let response = try await httpClient.execute(
            HTTPRequest(
                url: iconURL,
                headers: [
                    "Accept": "image/png, image/jpeg, image/x-icon, image/*;q=0.9, */*;q=0.1",
                    "User-Agent": "RSSReader/0 (Feed Icon Discovery)"
                ],
                timeoutInterval: timeoutInterval,
                maximumResponseBodyBytes: AppComposition.resourceBudgetContract
                    .feedIcon
                    .body
                    .maximumCompressedBodyBytes
            )
        )
        try Task.checkCancellation()
        guard (200...299).contains(response.statusCode) else {
            return nil
        }
        let iconBudget = AppComposition.resourceBudgetContract.feedIcon
        try iconBudget.body.validateCompressedBodyByteCount(Int64(response.body.count))
        try iconBudget.body.validateMIMEType(response.contentType)
        guard FeedIconImagePolicy.isSuitableRasterIcon(response.body, budget: iconBudget) else {
            return nil
        }

        try Task.checkCancellation()
        try await feedIconCache.storeImageData(response.body, for: iconURL)
        return response.body
    }

    private func fetchFeedHomeHTML(
        from url: URL,
        budget: FeedIconDiscoveryBudget
    ) async throws -> FeedIconHTMLDocument? {
        try Task.checkCancellation()
        guard let timeoutInterval = budget.requestTimeoutInterval(max: requestTimeoutInterval) else {
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
                    timeoutInterval: timeoutInterval,
                    maximumResponseBodyBytes: AppComposition.resourceBudgetContract
                        .discoveryHTML
                        .body
                        .maximumCompressedBodyBytes
                )
            )
            try Task.checkCancellation()
            guard let html = try HTMLDiscoveryResponseDecoder.decode(response) else { return nil }
            return FeedIconHTMLDocument(html: html, baseURL: response.url)
        } catch let error as CancellationError {
            throw error
        } catch {
            logger.debug(
                "Failed to load feed homepage for icon discovery from \(url.absoluteString): \(String(describing: error))"
            )
            return nil
        }
    }
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
        let htmlBudget = AppComposition.resourceBudgetContract.discoveryHTML
        let candidates = HTMLLinkDiscoveryParser.linkTagAttributes(
            in: html,
            maximumLinkTagCount: htmlBudget.maximumLinkTagCountToInspect
        ).compactMap { attributes -> FeedIconCandidate? in
            guard let href = attributes["href"],
                  let rel = attributes["rel"],
                  let priority = iconPriority(forRelValue: rel),
                  let url = URL(string: href, relativeTo: baseURL)?.absoluteURL,
                  isSupportedIconURL(url) else {
                return nil
            }

            return FeedIconCandidate(url: url, priority: priority)
        }

        return Array(deduplicated(
            candidates
                .sorted { lhs, rhs in
                    lhs.priority == rhs.priority
                        ? lhs.url.absoluteString < rhs.url.absoluteString
                        : lhs.priority < rhs.priority
                }
                .map(\.url)
        ).prefix(htmlBudget.maximumDiscoveryCandidateCount))
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

}

enum FeedIconImagePolicy {
    static func isSuitableRasterIcon(
        _ data: Data,
        budget: RuntimeImageInputBudget = AppComposition.resourceBudgetContract.feedIcon
    ) -> Bool {
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue else {
            return false
        }

        do {
            try budget.validatePixelDimensions(width: width, height: height)
        } catch {
            return false
        }

        guard let image = UIImage(data: data) else { return false }
        return isSuitableIconSize(image.size)
    }

    static func isSuitableIconSize(_ size: CGSize) -> Bool {
        guard size.width > 0, size.height > 0 else { return false }

        let aspectRatio = max(size.width, size.height) / min(size.width, size.height)
        return aspectRatio <= 2
    }
}
