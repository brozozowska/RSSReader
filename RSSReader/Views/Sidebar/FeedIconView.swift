import SwiftUI
import UIKit

struct FeedIconView: View {
    @Environment(\.appDependencies) private var dependencies
    @Environment(AppState.self) private var appState
    let feedID: UUID
    let siteURL: String?
    let iconURL: String?
    @State private var iconImage: Image?
    @State private var loadTask: Task<Void, Never>?

    var body: some View {
        Group {
            if let iconImage {
                iconImage
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        .frame(width: 20, height: 20)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .task(id: cacheOnlyLoadID) {
            let allowsNetworkDiscovery = appState.consumeFeedIconNetworkLoadRequest(for: feedID)
            await loadIcon(allowsNetworkDiscovery: allowsNetworkDiscovery)
        }
        .onChange(of: appState.feedIconReloadID) { _, _ in
            Task {
                await loadIcon(allowsNetworkDiscovery: true)
            }
        }
        .onChange(of: appState.feedIconCacheResetID) { _, _ in
            loadTask?.cancel()
            loadTask = nil
            iconImage = nil
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
    }

    private var cacheOnlyLoadID: FeedIconCacheOnlyLoadID {
        FeedIconCacheOnlyLoadID(
            siteURL: siteURL,
            iconURL: iconURL,
            sidebarReloadID: appState.sidebarReloadID
        )
    }

    private var resolvedURL: URL? {
        guard let iconURL else { return nil }
        return URL(string: iconURL)
    }

    private var resolvedSiteURL: URL? {
        guard let siteURL else { return nil }
        return URL(string: siteURL)
    }

    private var placeholder: some View {
        Image(systemName: "newspaper")
            .font(.body.weight(.medium))
            .foregroundStyle(.secondary)
    }

    @MainActor
    private func loadIcon(allowsNetworkDiscovery: Bool) async {
        loadTask?.cancel()
        iconImage = nil

        guard let resolvedURL else {
            return
        }

        let task = Task {
            if await loadFirstAvailableIcon(
                from: [resolvedURL],
                allowsNetworkDiscovery: allowsNetworkDiscovery,
                cacheAliasURL: nil
            ) {
                return
            }

            let fallbackOriginURL = resolvedSiteURL
                .flatMap(FeedIconCandidateBuilder.originURL(for:))
                ?? FeedIconCandidateBuilder.originURL(for: resolvedURL)

            if allowsNetworkDiscovery,
               let originURL = fallbackOriginURL,
               let html = await fetchSourceHomeHTML(from: originURL),
               await loadFirstAvailableIcon(
                from: FeedIconCandidateBuilder.htmlIconCandidates(in: html, baseURL: originURL),
                allowsNetworkDiscovery: true,
                cacheAliasURL: resolvedURL
               ) {
                return
            }

            _ = await loadFirstAvailableIcon(
                from: FeedIconCandidateBuilder.commonIconCandidates(for: fallbackOriginURL ?? resolvedURL),
                allowsNetworkDiscovery: allowsNetworkDiscovery,
                cacheAliasURL: allowsNetworkDiscovery ? resolvedURL : nil
            )
        }

        loadTask = task
        await task.value
    }

    private func loadFirstAvailableIcon(
        from iconURLs: [URL],
        allowsNetworkDiscovery: Bool,
        cacheAliasURL: URL?
    ) async -> Bool {
        for iconURL in iconURLs {
            do {
                let data: Data?
                if allowsNetworkDiscovery {
                    data = try await dependencies.feedIconCache.imageData(for: iconURL)
                } else {
                    data = try await dependencies.feedIconCache.cachedImageData(for: iconURL)
                }
                try Task.checkCancellation()

                guard let data,
                      let uiImage = UIImage(data: data),
                      FeedIconImagePolicy.isSuitableIconSize(uiImage.size) else {
                    continue
                }

                if allowsNetworkDiscovery,
                   let cacheAliasURL,
                   cacheAliasURL != iconURL {
                    try await dependencies.feedIconCache.storeImageData(data, for: cacheAliasURL)
                }

                await MainActor.run {
                    iconImage = Image(uiImage: uiImage)
                }
                return true
            } catch is CancellationError {
                return true
            } catch {
                dependencies.logger.debug(
                    "Failed to load feed icon for \(iconURL.absoluteString): \(String(describing: error))"
                )
            }
        }

        return false
    }

    private func fetchSourceHomeHTML(from url: URL) async -> String? {
        do {
            let response = try await dependencies.httpClient.execute(
                HTTPRequest(
                    url: url,
                    headers: [
                        "Accept": "text/html, application/xhtml+xml;q=0.9, */*;q=0.1",
                        "User-Agent": "RSSReader/0 (Feed Icon Discovery)"
                    ],
                    timeoutInterval: 8
                )
            )
            guard (200...299).contains(response.statusCode) else { return nil }
            return String(data: response.body, encoding: .utf8)
        } catch {
            dependencies.logger.debug(
                "Failed to load source homepage for icon discovery from \(url.absoluteString): \(String(describing: error))"
            )
            return nil
        }
    }
}

private struct FeedIconCacheOnlyLoadID: Hashable {
    let siteURL: String?
    let iconURL: String?
    let sidebarReloadID: UUID
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

    private static func isSupportedIconURL(_ url: URL) -> Bool {
        url.pathExtension.lowercased() != "svg"
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
    static func isSuitableIconSize(_ size: CGSize) -> Bool {
        guard size.width > 0, size.height > 0 else { return false }

        let aspectRatio = max(size.width, size.height) / min(size.width, size.height)
        return aspectRatio <= 2
    }
}
