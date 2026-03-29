import Foundation

public enum FeedRequestError: Error {
    case invalidURL(String)
}

public enum FeedFetchError: Error {
    case transport(FeedTransportError)
    case invalidStatusCode(Int)
    case unsupportedContentType(String?)
}

public enum FeedTransportError: Error, Sendable {
    case timedOut
    case cannotFindHost
    case cannotConnectToHost
    case dnsLookupFailed
    case networkConnectionLost
    case notConnectedToInternet
    case resourceUnavailable
    case internationalRoamingOff
    case callIsActive
    case dataNotAllowed
    case invalidResponse
    case unknown
}

public enum FeedFetchResult: Sendable {
    case fetched(FeedResponse)
    case notModified(FeedResponse)

    public var response: FeedResponse {
        switch self {
        case .fetched(let response), .notModified(let response):
            response
        }
    }
}

public struct FeedRequest: Sendable {
    public let feedID: UUID
    public let url: URL
    public let ifNoneMatch: String?
    public let ifModifiedSince: String?

    public init(
        feedID: UUID,
        url: URL,
        ifNoneMatch: String? = nil,
        ifModifiedSince: String? = nil
    ) {
        self.feedID = feedID
        self.url = url
        self.ifNoneMatch = Self.normalizeHeaderValue(ifNoneMatch)
        self.ifModifiedSince = Self.normalizeHeaderValue(ifModifiedSince)
    }

    public init(
        feedID: UUID,
        urlString: String,
        ifNoneMatch: String? = nil,
        ifModifiedSince: String? = nil
    ) throws {
        guard let url = URL(string: urlString) else {
            throw FeedRequestError.invalidURL(urlString)
        }

        self.init(
            feedID: feedID,
            url: url,
            ifNoneMatch: ifNoneMatch,
            ifModifiedSince: ifModifiedSince
        )
    }

    init(feed: Feed) throws {
        try self.init(
            feedID: feed.id,
            urlString: feed.url,
            ifNoneMatch: feed.lastETag,
            ifModifiedSince: feed.lastModifiedHeader
        )
    }

    public var headers: [String: String] {
        var headers = [
            "Accept": "application/rss+xml, application/atom+xml, application/xml, text/xml;q=0.9, */*;q=0.1",
            "User-Agent": Self.feedUserAgent
        ]

        if let ifNoneMatch, ifNoneMatch.isEmpty == false {
            headers["If-None-Match"] = ifNoneMatch
        }

        if let ifModifiedSince, ifModifiedSince.isEmpty == false {
            headers["If-Modified-Since"] = ifModifiedSince
        }

        return headers
    }

    public var httpRequest: HTTPRequest {
        HTTPRequest(url: url, headers: headers)
    }

    public var hasConditionalHeaders: Bool {
        ifNoneMatch != nil || ifModifiedSince != nil
    }

    private static func normalizeHeaderValue(_ value: String?) -> String? {
        guard let value else { return nil }

        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedValue.isEmpty == false else { return nil }
        return normalizedValue
    }

    private static let feedUserAgent: String = {
        let bundle = Bundle.main
        let bundleName = (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let bundleVersion = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let resolvedName = (bundleName?.isEmpty == false ? bundleName : nil) ?? "RSSReader"
        let resolvedVersion = (bundleVersion?.isEmpty == false ? bundleVersion : nil) ?? "0"

        return "\(resolvedName)/\(resolvedVersion) (Feed Fetch)"
    }()
}

public struct FeedResponse: Sendable {
    public let request: FeedRequest
    public let sourceURL: URL
    public let statusCode: Int
    public let headers: [String: String]
    public let body: Data

    public init(
        request: FeedRequest,
        sourceURL: URL,
        statusCode: Int,
        headers: [String: String],
        body: Data
    ) {
        self.request = request
        self.sourceURL = sourceURL
        self.statusCode = statusCode
        self.headers = headers.reduce(into: [String: String]()) { partialResult, entry in
            partialResult[entry.key.lowercased()] = entry.value
        }
        self.body = body
    }

    public init(request: FeedRequest, httpResponse: HTTPResponse) {
        self.init(
            request: request,
            sourceURL: httpResponse.url,
            statusCode: httpResponse.statusCode,
            headers: httpResponse.headers,
            body: httpResponse.body
        )
    }

    public var eTag: String? {
        headers["etag"]
    }

    public var lastModified: String? {
        headers["last-modified"]
    }

    public var contentType: String? {
        headers["content-type"]
    }

    public var normalizedContentType: String? {
        guard let contentType else { return nil }

        let rawValue = contentType
            .split(separator: ";", maxSplits: 1)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard let rawValue, rawValue.isEmpty == false else { return nil }
        return rawValue
    }

    public var isNotModified: Bool {
        statusCode == 304
    }
}
