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
        var preferredPreviewError: Error?
        var accessDeniedError: Error?
        var autodiscoveryCandidateCount = 0
        let maximumAutodiscoveryCandidateCount = AppComposition.resourceBudgetContract
            .discoveryHTML
            .maximumDiscoveryCandidateCount

        for feedURL in discoveryPlan.feedURLs {
            try Task.checkCancellation()

            do {
                return try await previewFeed(at: feedURL, stage: "direct")
            } catch let error as CancellationError {
                throw error
            } catch {
                logFailure(error, stage: "direct", requestedURL: feedURL)
                try stopIfRateLimited(error)
                if feedURL == discoveryPlan.preferredFeedURL { preferredPreviewError = error }
                lastPreviewError = error
                attemptedFeedURLs.insert(feedURL.absoluteString)
            }
        }

        siteDiscovery: for siteURL in discoveryPlan.siteURLs {
            try Task.checkCancellation()
            let discoveredFeedURLs: [URL]
            do {
                discoveredFeedURLs = try await discoverFeedURLs(from: siteURL)
            } catch let error as CancellationError {
                throw error
            } catch {
                try stopIfRateLimited(error)
                if (error as? FeedFetchError)?.httpStatusCode == 403 { accessDeniedError = error }
                continue
            }
            for feedURL in discoveredFeedURLs where attemptedFeedURLs.contains(feedURL.absoluteString) == false {
                try Task.checkCancellation()

                guard autodiscoveryCandidateCount < maximumAutodiscoveryCandidateCount else {
                    break siteDiscovery
                }
                autodiscoveryCandidateCount += 1

                do {
                    return try await previewFeed(at: feedURL, stage: "autodiscovered")
                } catch let error as CancellationError {
                    throw error
                } catch {
                    logFailure(error, stage: "autodiscovered", requestedURL: feedURL)
                    try stopIfRateLimited(error)
                    lastPreviewError = error
                    attemptedFeedURLs.insert(feedURL.absoluteString)
                }
            }
        }

        for feedURL in discoveryPlan.fallbackFeedURLs where attemptedFeedURLs.contains(feedURL.absoluteString) == false {
            try Task.checkCancellation()

            do {
                return try await previewFeed(at: feedURL, stage: "fallback")
            } catch let error as CancellationError {
                throw error
            } catch {
                logFailure(error, stage: "fallback", requestedURL: feedURL)
                try stopIfRateLimited(error)
                lastPreviewError = error
                attemptedFeedURLs.insert(feedURL.absoluteString)
            }
        }

        if let preferredPreviewError { throw preferredPreviewError }
        if let accessDeniedError { throw accessDeniedError }
        if discoveryPlan.fallbackFeedURLs.isEmpty == false {
            throw FeedManagementServiceError.feedDiscoveryFailed(urlString)
        }

        if let lastPreviewError {
            throw lastPreviewError
        }

        throw FeedManagementServiceError.feedDiscoveryFailed(urlString)
    }

    private func previewFeed(at feedURL: URL, stage: String) async throws -> FeedManagementFeedPreview {
        let normalizedURL = feedURL.absoluteString
        let request = FeedRequest(
            feedID: UUID(),
            url: feedURL,
            timeoutInterval: Self.previewRequestTimeoutInterval
        )
        let fetchResult = try await feedFetcher.fetch(request)
        let response = fetchResult.response
        let receivedAt = Date.now
        logger.debug("feed_discovery stage=\(stage) requested=\(FeedHTTPResponseDiagnostics.safeURL(feedURL)) final=\(FeedHTTPResponseDiagnostics.safeURL(response.sourceURL)) status=\(response.statusCode)")
        guard case .fetched(let response) = fetchResult else {
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
            existingFeedID: existingFeed?.id,
            initialFetchSnapshot: FeedManagementFeedDiscoveryPlanner.isRedditURL(response.sourceURL)
                ? FeedInitialFetchSnapshot(response: response, receivedAt: receivedAt) : nil
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
            let retryAt = response.statusCode == 429 ? FeedHTTPResponseDiagnostics.retryAt(for: response) : nil
            logger.debug("feed_discovery stage=html requested=\(FeedHTTPResponseDiagnostics.safeURL(siteURL)) final=\(FeedHTTPResponseDiagnostics.safeURL(response.url)) status=\(response.statusCode) retryAt=\(retryAt?.description ?? "none")")
            if response.statusCode == 429 {
                throw FeedFetchError.rateLimited(retryAt: retryAt, responseURL: FeedHTTPResponseDiagnostics.safeURL(response.url))
            }
            if response.statusCode == 403 {
                throw FeedFetchError.invalidStatusCode(403, responseURL: FeedHTTPResponseDiagnostics.safeURL(response.url))
            }
            guard let html = try HTMLDiscoveryResponseDecoder.decode(response) else { return [] }
            try Task.checkCancellation()
            return FeedManagementFeedDiscoveryPlanner.autodiscoveredFeedURLs(
                in: html,
                baseURL: response.url
            )
        } catch let error as CancellationError {
            throw error
        } catch {
            logFailure(error, stage: "html", requestedURL: siteURL)
            if (error as? FeedFetchError)?.httpStatusCode == 403 || (error as? FeedFetchError)?.httpStatusCode == 429 {
                throw error
            }
            return []
        }
    }

    private static let previewRequestTimeoutInterval: TimeInterval = 8

    private func stopIfRateLimited(_ error: Error) throws {
        if let error = error as? FeedFetchError, error.httpStatusCode == 429 { throw error }
    }

    private func logFailure(_ error: Error, stage: String, requestedURL: URL) {
        var finalURL = "unavailable"
        var retryAt: Date?
        if let fetchError = error as? FeedFetchError {
            switch fetchError {
            case .invalidStatusCode(_, let url): finalURL = url ?? finalURL
            case .rateLimited(let date, let url):
                finalURL = url ?? finalURL
                retryAt = date
            default: break
            }
        }
        if let url = URL(string: finalURL), url.host != nil {
            finalURL = FeedHTTPResponseDiagnostics.safeURL(url)
        }
        logger.debug("feed_discovery stage=\(stage) requested=\(FeedHTTPResponseDiagnostics.safeURL(requestedURL)) final=\(finalURL) status=\((error as? FeedFetchError)?.httpStatusCode.map(String.init) ?? "unavailable") retryAt=\(retryAt?.description ?? "none") failure=\(String(describing: type(of: error)))")
    }
}
