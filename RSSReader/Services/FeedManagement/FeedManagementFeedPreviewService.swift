import Foundation

@MainActor
struct FeedManagementFeedPreviewService {
    let logger: Logging
    let httpClient: any HTTPClient
    let feedFetcher: any FeedFetching
    let feedParsingWorker: any FeedParsingWorking
    let normalizationPolicy: FeedManagementNormalizationPolicy

    func previewFeed(urlString: String) async throws -> FeedManagementFeedPreview {
        try Task.checkCancellation()

        let discoveryPlan = try FeedManagementFeedDiscoveryPlanner.makePlan(for: urlString)
        var attemptedFeedURLs: Set<String> = []
        var lastPreviewError: Error?
        var autodiscoveryCandidateCount = 0
        let maximumAutodiscoveryCandidateCount = AppComposition.resourceBudgetContract
            .discoveryHTML
            .maximumDiscoveryCandidateCount

        for feedURL in discoveryPlan.feedURLs {
            try Task.checkCancellation()

            do {
                return try await previewFeed(at: feedURL)
            } catch let error as CancellationError {
                throw error
            } catch {
                lastPreviewError = error
                attemptedFeedURLs.insert(feedURL.absoluteString)
                logger.debug("Feed management feed discovery candidate failed for \(feedURL.absoluteString): \(error)")
            }
        }

        siteDiscovery: for siteURL in discoveryPlan.siteURLs {
            try Task.checkCancellation()
            let discoveredFeedURLs = try await discoverFeedURLs(from: siteURL)
            for feedURL in discoveredFeedURLs where attemptedFeedURLs.contains(feedURL.absoluteString) == false {
                try Task.checkCancellation()

                guard autodiscoveryCandidateCount < maximumAutodiscoveryCandidateCount else {
                    break siteDiscovery
                }
                autodiscoveryCandidateCount += 1

                do {
                    return try await previewFeed(at: feedURL)
                } catch let error as CancellationError {
                    throw error
                } catch {
                    lastPreviewError = error
                    attemptedFeedURLs.insert(feedURL.absoluteString)
                    logger.debug("Feed management autodiscovered feed candidate failed for \(feedURL.absoluteString): \(error)")
                }
            }
        }

        for feedURL in discoveryPlan.fallbackFeedURLs where attemptedFeedURLs.contains(feedURL.absoluteString) == false {
            try Task.checkCancellation()

            do {
                return try await previewFeed(at: feedURL)
            } catch let error as CancellationError {
                throw error
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
        let parsingResult = try await feedParsingWorker.parsePreview(response)
        let metadata = parsingResult.feed.metadata
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
            kind: parsingResult.feed.kind,
            parserAnomalyCount: parsingResult.diagnostics.parserAnomalies.count,
            rejectedEntryCount: parsingResult.diagnostics.rejectedEntries.count,
            existingFeedID: existingFeed?.id
        )
    }

    private func discoverFeedURLs(from siteURL: URL) async throws -> [URL] {
        do {
            try Task.checkCancellation()
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
                        .body
                        .maximumCompressedBodyBytes
                )
            )
            try Task.checkCancellation()
            guard let html = try HTMLDiscoveryResponseDecoder.decode(response) else { return [] }
            try Task.checkCancellation()
            return FeedManagementFeedDiscoveryPlanner.autodiscoveredFeedURLs(
                in: html,
                baseURL: response.url
            )
        } catch let error as CancellationError {
            throw error
        } catch {
            logger.debug("Feed management HTML feed autodiscovery failed for \(siteURL.absoluteString): \(error)")
            return []
        }
    }

    private static let previewRequestTimeoutInterval: TimeInterval = 8
}
