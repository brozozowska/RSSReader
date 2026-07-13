import Foundation

public nonisolated struct HTTPRequest: Sendable {
    public let url: URL
    public let headers: [String: String]
    public let timeoutInterval: TimeInterval
    public let maximumResponseBodyBytes: Int64

    public init(
        url: URL,
        headers: [String: String] = [:],
        timeoutInterval: TimeInterval = 30,
        maximumResponseBodyBytes: Int64
    ) {
        precondition(maximumResponseBodyBytes > 0)
        precondition(maximumResponseBodyBytes <= Int64(Int.max))
        self.url = url
        self.headers = headers
        self.timeoutInterval = timeoutInterval
        self.maximumResponseBodyBytes = maximumResponseBodyBytes
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

public nonisolated struct HTTPResponse: Sendable {
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

public nonisolated enum HTTPClientError: Error, Equatable, Sendable {
    case invalidResponse
    case responseBodyTooLarge(maximumBytes: Int64, actualBytes: Int64)
}

public protocol HTTPClient: Sendable {
    func execute(_ request: HTTPRequest) async throws -> HTTPResponse
}

public extension URLSessionConfiguration {
    nonisolated static func feedRequestsDefault() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.waitsForConnectivity = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return configuration
    }
}

public nonisolated final class URLSessionHTTPClient: HTTPClient, @unchecked Sendable {
    private let responseLoader: BoundedHTTPResponseLoader

    public init(
        configuration: URLSessionConfiguration = .feedRequestsDefault()
    ) {
        self.responseLoader = BoundedHTTPResponseLoader(configuration: configuration)
    }

    public func execute(_ request: HTTPRequest) async throws -> HTTPResponse {
        try await responseLoader.execute(request)
    }

    deinit {
        responseLoader.invalidate()
    }
}

private nonisolated final class BoundedHTTPResponseLoader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private struct LoadingState {
        let request: HTTPRequest
        let continuation: CheckedContinuation<HTTPResponse, any Error>
        var response: HTTPURLResponse?
        var body = Data()
    }

    private let lock = NSLock()
    private let delegateQueue: OperationQueue
    private var statesByTaskIdentifier: [Int: LoadingState] = [:]
    private var session: URLSession?

    init(configuration: URLSessionConfiguration) {
        let delegateQueue = OperationQueue()
        delegateQueue.name = "RSSReader.BoundedHTTPResponseLoader"
        delegateQueue.maxConcurrentOperationCount = 1
        self.delegateQueue = delegateQueue
        super.init()
        self.session = URLSession(
            configuration: configuration,
            delegate: self,
            delegateQueue: delegateQueue
        )
    }

    func execute(_ request: HTTPRequest) async throws -> HTTPResponse {
        try Task.checkCancellation()
        let cancellation = HTTPRequestCancellation()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                guard let session else {
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                    return
                }

                let task = session.dataTask(with: request.urlRequest)
                statesByTaskIdentifier[task.taskIdentifier] = LoadingState(
                    request: request,
                    continuation: continuation
                )
                lock.unlock()

                cancellation.install { [weak self] in
                    self?.cancel(task: task)
                }
                task.resume()
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    func invalidate() {
        lock.lock()
        let states = Array(statesByTaskIdentifier.values)
        statesByTaskIdentifier.removeAll()
        let session = self.session
        self.session = nil
        lock.unlock()

        session?.invalidateAndCancel()
        for state in states {
            state.continuation.resume(throwing: CancellationError())
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        guard let httpResponse = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            fail(task: dataTask, error: HTTPClientError.invalidResponse)
            return
        }

        lock.lock()
        guard var state = statesByTaskIdentifier[dataTask.taskIdentifier] else {
            lock.unlock()
            completionHandler(.cancel)
            return
        }

        let declaredBodyBytes = httpResponse.expectedContentLength
        let rejectsDeclaredBodySize = Self.responseCanHaveBody(statusCode: httpResponse.statusCode)
            && declaredBodyBytes > state.request.maximumResponseBodyBytes

        if rejectsDeclaredBodySize {
            statesByTaskIdentifier[dataTask.taskIdentifier] = nil
            lock.unlock()
            completionHandler(.cancel)
            state.continuation.resume(
                throwing: HTTPClientError.responseBodyTooLarge(
                    maximumBytes: state.request.maximumResponseBodyBytes,
                    actualBytes: declaredBodyBytes
                )
            )
            dataTask.cancel()
            return
        }

        state.response = httpResponse
        statesByTaskIdentifier[dataTask.taskIdentifier] = state
        lock.unlock()
        completionHandler(.allow)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        lock.lock()
        guard var state = statesByTaskIdentifier[dataTask.taskIdentifier] else {
            lock.unlock()
            return
        }

        let currentBodyBytes = Int64(state.body.count)
        let incomingBodyBytes = Int64(data.count)
        let remainingBodyBytes = state.request.maximumResponseBodyBytes - currentBodyBytes

        guard incomingBodyBytes <= remainingBodyBytes else {
            statesByTaskIdentifier[dataTask.taskIdentifier] = nil
            lock.unlock()

            let (actualBodyBytes, overflowed) = currentBodyBytes.addingReportingOverflow(incomingBodyBytes)
            state.continuation.resume(
                throwing: HTTPClientError.responseBodyTooLarge(
                    maximumBytes: state.request.maximumResponseBodyBytes,
                    actualBytes: overflowed ? Int64.max : actualBodyBytes
                )
            )
            dataTask.cancel()
            return
        }

        state.body.append(data)
        statesByTaskIdentifier[dataTask.taskIdentifier] = state
        lock.unlock()
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        lock.lock()
        let state = statesByTaskIdentifier.removeValue(forKey: task.taskIdentifier)
        lock.unlock()

        guard let state else { return }

        if let error {
            state.continuation.resume(throwing: error)
            return
        }

        guard let response = state.response else {
            state.continuation.resume(throwing: HTTPClientError.invalidResponse)
            return
        }

        let headers = response.allHeaderFields.reduce(into: [String: String]()) { partialResult, entry in
            guard let key = entry.key as? String else { return }
            partialResult[key] = String(describing: entry.value)
        }

        state.continuation.resume(
            returning: HTTPResponse(
                url: response.url ?? state.request.url,
                statusCode: response.statusCode,
                headers: headers,
                body: state.body
            )
        )
    }

    private func cancel(task: URLSessionTask) {
        lock.lock()
        let state = statesByTaskIdentifier.removeValue(forKey: task.taskIdentifier)
        lock.unlock()

        task.cancel()
        state?.continuation.resume(throwing: CancellationError())
    }

    private func fail(task: URLSessionTask, error: any Error) {
        lock.lock()
        let state = statesByTaskIdentifier.removeValue(forKey: task.taskIdentifier)
        lock.unlock()

        task.cancel()
        state?.continuation.resume(throwing: error)
    }

    private static func responseCanHaveBody(statusCode: Int) -> Bool {
        (100...199).contains(statusCode) == false
            && statusCode != 204
            && statusCode != 304
    }
}

private nonisolated final class HTTPRequestCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancellationAction: (@Sendable () -> Void)?
    private var isCancelled = false

    func install(_ action: @escaping @Sendable () -> Void) {
        lock.lock()
        if isCancelled {
            lock.unlock()
            action()
            return
        }
        cancellationAction = action
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let action = cancellationAction
        cancellationAction = nil
        lock.unlock()
        action?()
    }
}
