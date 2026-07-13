import Foundation
@testable import RSSReader

actor ScriptedHTTPClient: HTTPClient {
    enum Step: Sendable {
        case response(statusCode: Int, headers: [String: String], body: String)
        case dataResponse(statusCode: Int, headers: [String: String], body: Data)
        case delayedResponse(statusCode: Int, headers: [String: String], body: String, delayNanoseconds: UInt64)
        case invalidResponse
        case responseBodyTooLarge(maximumBytes: Int64, actualBytes: Int64)
        case urlError(URLError.Code)
        case cancelled
    }

    private var steps: [Step]
    private var responsesByURL: [String: Step]
    private var requests: [HTTPRequest] = []
    private var inFlightExecutions = 0
    private var maxConcurrentExecutionCount = 0

    init(
        steps: [Step] = [],
        responsesByURL: [String: Step] = [:]
    ) {
        self.steps = steps
        self.responsesByURL = responsesByURL
    }

    private func beginExecution() {
        inFlightExecutions += 1
        maxConcurrentExecutionCount = max(maxConcurrentExecutionCount, inFlightExecutions)
    }

    private func endExecution() {
        inFlightExecutions = max(0, inFlightExecutions - 1)
    }

    private func makeResponse(
        request: HTTPRequest,
        statusCode: Int,
        headers: [String: String],
        body: Data
    ) async -> HTTPResponse {
        await MainActor.run {
            HTTPResponse(
                url: request.url,
                statusCode: statusCode,
                headers: headers,
                body: body
            )
        }
    }

    func execute(_ request: HTTPRequest) async throws -> HTTPResponse {
        requests.append(request)
        beginExecution()
        defer { endExecution() }

        let requestURLString = await MainActor.run {
            request.url.absoluteString
        }

        let step: Step
        if let routedStep = responsesByURL.removeValue(forKey: requestURLString) {
            step = routedStep
        } else if steps.isEmpty == false {
            step = steps.removeFirst()
        } else {
            throw URLError(.badServerResponse)
        }

        switch step {
        case .response(let statusCode, let headers, let body):
            return await makeResponse(
                request: request,
                statusCode: statusCode,
                headers: headers,
                body: Data(body.utf8)
            )
        case .dataResponse(let statusCode, let headers, let body):
            return await makeResponse(
                request: request,
                statusCode: statusCode,
                headers: headers,
                body: body
            )
        case .delayedResponse(let statusCode, let headers, let body, let delayNanoseconds):
            try await Task.sleep(nanoseconds: delayNanoseconds)
            return await makeResponse(
                request: request,
                statusCode: statusCode,
                headers: headers,
                body: Data(body.utf8)
            )
        case .invalidResponse:
            throw HTTPClientError.invalidResponse
        case .responseBodyTooLarge(let maximumBytes, let actualBytes):
            throw HTTPClientError.responseBodyTooLarge(
                maximumBytes: maximumBytes,
                actualBytes: actualBytes
            )
        case .urlError(let code):
            throw URLError(code)
        case .cancelled:
            throw CancellationError()
        }
    }

    func recordedRequests() -> [HTTPRequest] {
        requests
    }

    func maxConcurrentExecutions() -> Int {
        maxConcurrentExecutionCount
    }
}
