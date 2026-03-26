import Foundation

public protocol FeedFetching: Sendable {
    func fetch(_ request: FeedRequest) async throws -> FeedResponse
}

public struct FeedFetcher: FeedFetching {
    private let httpClient: any HTTPClient
    private let supportedContentTypes: Set<String> = [
        "application/atom+xml",
        "application/rdf+xml",
        "application/rss+xml",
        "application/xml",
        "text/xml"
    ]

    public init(httpClient: any HTTPClient) {
        self.httpClient = httpClient
    }

    public func fetch(_ request: FeedRequest) async throws -> FeedResponse {
        let httpResponse = try await httpClient.execute(request.httpRequest)
        let response = FeedResponse(request: request, httpResponse: httpResponse)

        try validateStatusCode(response.statusCode)
        try validateContentType(response)

        return response
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
}
