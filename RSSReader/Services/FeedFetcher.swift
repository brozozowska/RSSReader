import Foundation

public protocol FeedFetching: Sendable {
    func fetch(_ request: FeedRequest) async throws -> FeedResponse
}

public struct FeedFetcher: FeedFetching {
    private let httpClient: any HTTPClient

    public init(httpClient: any HTTPClient) {
        self.httpClient = httpClient
    }

    public func fetch(_ request: FeedRequest) async throws -> FeedResponse {
        let httpResponse = try await httpClient.execute(request.httpRequest)
        return FeedResponse(request: request, httpResponse: httpResponse)
    }
}
