import Foundation

@MainActor
struct FeedManagementFeedPreviewService {
    let logger: Logging
    let httpClient: any HTTPClient
    let feedFetcher: any FeedFetching
    let normalizationPolicy: FeedManagementNormalizationPolicy

    func previewFeed(urlString: String) async throws -> FeedManagementFeedPreview {
        let discoveryPlan = try FeedManagementFeedDiscoveryPlanner.makePlan(for: urlString)
        var attemptedFeedURLs: Set<String> = []
        var lastPreviewError: Error?

        for feedURL in discoveryPlan.feedURLs {
            do {
                return try await previewFeed(at: feedURL)
            } catch {
                lastPreviewError = error
                attemptedFeedURLs.insert(feedURL.absoluteString)
                logger.debug("Feed management feed discovery candidate failed for \(feedURL.absoluteString): \(error)")
            }
        }

        for siteURL in discoveryPlan.siteURLs {
            let discoveredFeedURLs = await discoverFeedURLs(from: siteURL)
            for feedURL in discoveredFeedURLs where attemptedFeedURLs.contains(feedURL.absoluteString) == false {
                do {
                    return try await previewFeed(at: feedURL)
                } catch {
                    lastPreviewError = error
                    attemptedFeedURLs.insert(feedURL.absoluteString)
                    logger.debug("Feed management autodiscovered feed candidate failed for \(feedURL.absoluteString): \(error)")
                }
            }
        }

        for feedURL in discoveryPlan.fallbackFeedURLs where attemptedFeedURLs.contains(feedURL.absoluteString) == false {
            do {
                return try await previewFeed(at: feedURL)
            } catch {
                lastPreviewError = error
                attemptedFeedURLs.insert(feedURL.absoluteString)
                logger.debug("Feed management fallback feed discovery candidate failed for \(feedURL.absoluteString): \(error)")
            }
        }

        if discoveryPlan.fallbackFeedURLs.isEmpty == false {
            throw FeedManagementServiceError.feedDiscoveryFailed(urlString)
        }

        if let lastPreviewError {
            throw lastPreviewError
        }

        throw FeedManagementServiceError.feedDiscoveryFailed(urlString)
    }

    private func previewFeed(at feedURL: URL) async throws -> FeedManagementFeedPreview {
        let normalizedURL = feedURL.absoluteString
        let request = FeedRequest(
            feedID: UUID(),
            url: feedURL,
            timeoutInterval: Self.previewRequestTimeoutInterval
        )
        let fetchResult = try await feedFetcher.fetch(request)
        guard case .fetched(let response) = fetchResult else {
            logger.error("Skipped feed management preview because fetch returned not-modified for \(normalizedURL)")
            throw FeedManagementServiceError.previewUnavailableForNotModifiedResponse
        }
        let pipelineResult = try FeedParserService.parsePipelineResult(response)
        let metadata = pipelineResult.feed.metadata
        let resolvedFeedURL = response.sourceURL.absoluteString
        let existingFeed = try normalizationPolicy.existingFeed(
            resolvedFeedURL: resolvedFeedURL,
            requestedURL: normalizedURL
        )

        return FeedManagementFeedPreview(
            requestedURL: normalizedURL,
            resolvedFeedURL: resolvedFeedURL,
            title: normalizationPolicy.normalizedNonEmptyString(metadata.title) ?? resolvedFeedURL,
            subtitle: normalizationPolicy.normalizedNonEmptyString(metadata.subtitle),
            siteURL: normalizationPolicy.normalizedNonEmptyString(metadata.siteURL),
            iconURL: normalizationPolicy.normalizedNonEmptyString(metadata.iconURL),
            language: normalizationPolicy.normalizedNonEmptyString(metadata.language),
            kind: pipelineResult.feed.kind,
            parserAnomalyCount: pipelineResult.diagnostics.parserAnomalies.count,
            rejectedEntryCount: pipelineResult.diagnostics.rejectedEntries.count,
            existingFeedID: existingFeed?.id
        )
    }

    private func discoverFeedURLs(from siteURL: URL) async -> [URL] {
        do {
            let response = try await httpClient.execute(
                HTTPRequest(
                    url: siteURL,
                    headers: [
                        "Accept": "text/html, application/xhtml+xml;q=0.9, */*;q=0.1",
                        "User-Agent": "RSSReader/0 (Feed Discovery)"
                    ],
                    timeoutInterval: Self.previewRequestTimeoutInterval,
                    maximumResponseBodyBytes: AppComposition.resourceBudgetContract
                        .discoveryHTML
                        .maximumCompressedBodyBytes
                )
            )
            guard (200...299).contains(response.statusCode),
                  let html = String(data: response.body, encoding: .utf8) else {
                return []
            }
            return FeedManagementFeedDiscoveryPlanner.autodiscoveredFeedURLs(
                in: html,
                baseURL: response.url
            )
        } catch {
            logger.debug("Feed management HTML feed autodiscovery failed for \(siteURL.absoluteString): \(error)")
            return []
        }
    }

    private static let previewRequestTimeoutInterval: TimeInterval = 8
}
