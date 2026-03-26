import Foundation

public enum FeedRequestError: Error {
    case invalidURL(String)
}

public enum FeedFetchError: Error {
    case invalidStatusCode(Int)
    case unsupportedContentType(String?)
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
        self.ifNoneMatch = ifNoneMatch
        self.ifModifiedSince = ifModifiedSince
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

    public var headers: [String: String] {
        var headers = [
            "Accept": "application/rss+xml, application/atom+xml, application/xml, text/xml;q=0.9, */*;q=0.1"
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
