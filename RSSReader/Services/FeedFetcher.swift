import Foundation

typealias FeedFetchLogSink = @Sendable (FeedFetchLog) async -> Void

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
        var lastError: Error?

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

                lastError = error

                let shouldRetry = isTransientNetworkError(error) && attempt < retryPolicy.maxAttempts
                guard shouldRetry else {
                    await logSink(makeFailureLog(for: request, error: error))
                    throw error
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

        throw lastError ?? FeedFetchError.invalidStatusCode(-1)
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

    private func isTransientNetworkError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else {
            return false
        }

        switch urlError.code {
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

    private func makeLog(for result: FeedFetchResult) -> FeedFetchLog {
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

        return FeedFetchLog(
            feedID: response.request.feedID,
            status: status,
            httpCode: response.statusCode,
            message: message
        )
    }

    private func makeFailureLog(for request: FeedRequest, error: Error) -> FeedFetchLog {
        let httpCode: Int? = if case .invalidStatusCode(let statusCode) = error as? FeedFetchError {
            statusCode
        } else {
            nil
        }

        return FeedFetchLog(
            feedID: request.feedID,
            status: "failed",
            httpCode: httpCode,
            message: String(describing: error)
        )
    }
}
