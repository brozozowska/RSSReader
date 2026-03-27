import Foundation

public struct HTTPRequest: Sendable {
    public let url: URL
    public let headers: [String: String]
    public let timeoutInterval: TimeInterval

    public init(
        url: URL,
        headers: [String: String] = [:],
        timeoutInterval: TimeInterval = 30
    ) {
        self.url = url
        self.headers = headers
        self.timeoutInterval = timeoutInterval
    }

    var urlRequest: URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeoutInterval

        for (header, value) in headers {
            request.setValue(value, forHTTPHeaderField: header)
        }

        return request
    }
}

public struct HTTPResponse: Sendable {
    public let url: URL
    public let statusCode: Int
    public let headers: [String: String]
    public let body: Data

    public init(
        url: URL,
        statusCode: Int,
        headers: [String: String],
        body: Data
    ) {
        self.url = url
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }
}

public enum HTTPClientError: Error {
    case invalidResponse
}

public protocol HTTPClient: Sendable {
    func execute(_ request: HTTPRequest) async throws -> HTTPResponse
}

public extension URLSessionConfiguration {
    static func feedRequestsDefault() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.waitsForConnectivity = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return configuration
    }
}

public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    public init(
        session: URLSession = URLSession(configuration: .feedRequestsDefault())
    ) {
        self.session = session
    }

    public func execute(_ request: HTTPRequest) async throws -> HTTPResponse {
        let (data, response) = try await session.data(for: request.urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw HTTPClientError.invalidResponse
        }

        let headers = httpResponse.allHeaderFields.reduce(into: [String: String]()) { partialResult, entry in
            guard let key = entry.key as? String else { return }
            partialResult[key] = String(describing: entry.value)
        }

        return HTTPResponse(
            url: httpResponse.url ?? request.url,
            statusCode: httpResponse.statusCode,
            headers: headers,
            body: data
        )
    }
}
