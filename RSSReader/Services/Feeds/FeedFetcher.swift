import Foundation

typealias FeedFetchLogSink = @Sendable (FeedFetchLogEntry) async -> Void

public struct FeedRetryPolicy: Sendable {
    public let maxAttempts: Int
    public let baseDelayNanoseconds: UInt64

    public init(
        maxAttempts: Int = 3,
        baseDelayNanoseconds: UInt64 = 500_000_000
    ) {
        self.maxAttempts = max(1, maxAttempts)
        self.baseDelayNanoseconds = baseDelayNanoseconds
    }

    func delayNanoseconds(forAttempt attempt: Int) -> UInt64 {
        guard attempt > 1 else { return 0 }

        let exponent = attempt - 2
        let multiplier = UInt64(1 << exponent)
        return baseDelayNanoseconds * multiplier
    }
}

public protocol FeedFetching: Sendable {
    func fetch(_ request: FeedRequest) async throws -> FeedFetchResult
}

public struct FeedFetcher: FeedFetching {
    private let httpClient: any HTTPClient
    private let retryPolicy: FeedRetryPolicy
    private let logSink: FeedFetchLogSink
    private let supportedContentTypes: Set<String> = [
        "application/atom+xml",
        "application/rdf+xml",
        "application/rss+xml",
        "application/xml",
        "text/xml"
    ]

    public init(
        httpClient: any HTTPClient,
        retryPolicy: FeedRetryPolicy = FeedRetryPolicy()
    ) {
        self.init(
            httpClient: httpClient,
            retryPolicy: retryPolicy,
            logSink: { _ in }
        )
    }

    init(
        httpClient: any HTTPClient,
        retryPolicy: FeedRetryPolicy = FeedRetryPolicy(),
        logSink: @escaping FeedFetchLogSink
    ) {
        self.httpClient = httpClient
        self.retryPolicy = retryPolicy
        self.logSink = logSink
    }

    public func fetch(_ request: FeedRequest) async throws -> FeedFetchResult {
        var lastError: FeedFetchError?

        for attempt in 1...retryPolicy.maxAttempts {
            do {
                let httpResponse = try await httpClient.execute(request.httpRequest)
                let response = FeedResponse(request: request, httpResponse: httpResponse)

                try validateStatusCode(response.statusCode)
                try validateContentType(response)

                if response.isNotModified {
                    let result = FeedFetchResult.notModified(response)
                    await logSink(makeLog(for: result))
                    return result
                }

                let result = FeedFetchResult.fetched(response)
                await logSink(makeLog(for: result))
                return result
            } catch {
                if error is CancellationError {
                    throw error
                }

                let feedError = mapToFeedFetchError(error)
                lastError = feedError

                let shouldRetry = isTransientTransportError(feedError) && attempt < retryPolicy.maxAttempts
                guard shouldRetry else {
                    await logSink(makeFailureLog(for: request, error: feedError))
                    throw feedError
                }

                let delayNanoseconds = retryPolicy.delayNanoseconds(forAttempt: attempt + 1)
                if delayNanoseconds > 0 {
                    try await Task.sleep(nanoseconds: delayNanoseconds)
                }
            }
        }

        if let lastError {
            await logSink(makeFailureLog(for: request, error: lastError))
            throw lastError
        }

        throw lastError ?? FeedFetchError.transport(.unknown)
    }

    private func validateStatusCode(_ statusCode: Int) throws {
        let isSuccessfulResponse = (200...299).contains(statusCode)
        let isNotModifiedResponse = statusCode == 304

        guard isSuccessfulResponse || isNotModifiedResponse else {
            throw FeedFetchError.invalidStatusCode(statusCode)
        }
    }

    private func validateContentType(_ response: FeedResponse) throws {
        guard response.isNotModified == false else {
            return
        }

        guard let contentType = response.normalizedContentType else {
            throw FeedFetchError.unsupportedContentType(response.contentType)
        }

        let isSupportedContentType =
            supportedContentTypes.contains(contentType) ||
            contentType.hasSuffix("+xml")

        guard isSupportedContentType else {
            throw FeedFetchError.unsupportedContentType(response.contentType)
        }
    }

    private func mapToFeedFetchError(_ error: Error) -> FeedFetchError {
        if let feedError = error as? FeedFetchError {
            return feedError
        }

        if let httpClientError = error as? HTTPClientError {
            switch httpClientError {
            case .invalidResponse:
                return .transport(.invalidResponse)
            }
        }

        guard let urlError = error as? URLError else {
            return .transport(.unknown)
        }

        switch urlError.code {
        case .timedOut:
            return .transport(.timedOut)
        case .cannotFindHost:
            return .transport(.cannotFindHost)
        case .cannotConnectToHost:
            return .transport(.cannotConnectToHost)
        case .dnsLookupFailed:
            return .transport(.dnsLookupFailed)
        case .networkConnectionLost:
            return .transport(.networkConnectionLost)
        case .notConnectedToInternet:
            return .transport(.notConnectedToInternet)
        case .resourceUnavailable:
            return .transport(.resourceUnavailable)
        case .internationalRoamingOff:
            return .transport(.internationalRoamingOff)
        case .callIsActive:
            return .transport(.callIsActive)
        case .dataNotAllowed:
            return .transport(.dataNotAllowed)
        default:
            return .transport(.unknown)
        }
    }

    private func isTransientTransportError(_ error: FeedFetchError) -> Bool {
        guard case .transport(let transportError) = error else {
            return false
        }

        switch transportError {
        case .timedOut,
                .cannotFindHost,
                .cannotConnectToHost,
                .dnsLookupFailed,
                .networkConnectionLost,
                .notConnectedToInternet,
                .resourceUnavailable,
                .internationalRoamingOff,
                .callIsActive,
                .dataNotAllowed:
            return true
        default:
            return false
        }
    }

    private func makeLog(for result: FeedFetchResult) -> FeedFetchLogEntry {
        let response = result.response

        let status: String = switch result {
        case .fetched:
            "fetched"
        case .notModified:
            "not_modified"
        }

        let message: String? = switch result {
        case .fetched:
            nil
        case .notModified:
            "Feed not modified"
        }

        return FeedFetchLogEntry(
            feedID: response.request.feedID,
            status: status,
            httpCode: response.statusCode,
            message: message
        )
    }

    private func makeFailureLog(for request: FeedRequest, error: Error) -> FeedFetchLogEntry {
        let httpCode: Int? = if case .invalidStatusCode(let statusCode) = error as? FeedFetchError {
            statusCode
        } else {
            nil
        }

        return FeedFetchLogEntry(
            feedID: request.feedID,
            status: "failed",
            httpCode: httpCode,
            message: String(describing: error)
        )
    }
}
