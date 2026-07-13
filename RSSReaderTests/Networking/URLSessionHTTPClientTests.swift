import Foundation
import Testing
@testable import RSSReader

@Suite("Networking / Bounded HTTP Response Loading")
struct URLSessionHTTPClientTests {
    @Test
    func rejectsDeclaredContentLengthBeforeLoadingBody() async throws {
        let url = makeURL("declared-content-length")
        let maximumBytes: Int64 = 5
        BoundedHTTPURLProtocol.register(
            .init(
                headers: ["Content-Length": "6"],
                chunks: [Data(repeating: 1, count: 6)]
            ),
            for: url
        )
        defer { BoundedHTTPURLProtocol.unregister(url) }

        await expectBodyTooLarge(
            url: url,
            maximumBytes: maximumBytes,
            expectedActualBytes: 6
        )
    }

    @Test
    func acceptsResponseWithoutContentLengthWhenActualBodyFits() async throws {
        let url = makeURL("missing-content-length")
        BoundedHTTPURLProtocol.register(
            .init(chunks: [Data("abc".utf8), Data("def".utf8)]),
            for: url
        )
        defer { BoundedHTTPURLProtocol.unregister(url) }

        let response = try await makeClient().execute(
            HTTPRequest(url: url, maximumResponseBodyBytes: 6)
        )

        #expect(response.statusCode == 200)
        #expect(String(data: response.body, encoding: .utf8) == "abcdef")
    }

    @Test
    func rejectsActualBodyWhenContentLengthIsFalselyLow() async throws {
        let url = makeURL("false-content-length")
        BoundedHTTPURLProtocol.register(
            .init(
                headers: ["Content-Length": "2"],
                chunks: [Data(repeating: 1, count: 3), Data(repeating: 2, count: 3)]
            ),
            for: url
        )
        defer { BoundedHTTPURLProtocol.unregister(url) }

        await expectBodyTooLarge(
            url: url,
            maximumBytes: 5,
            expectedActualBytes: 6
        )
    }

    @Test
    func rejectsChunkedResponseAsSoonAsActualBodyExceedsLimit() async throws {
        let url = makeURL("chunked-response")
        BoundedHTTPURLProtocol.register(
            .init(
                headers: ["Transfer-Encoding": "chunked"],
                chunks: [
                    Data(repeating: 1, count: 2),
                    Data(repeating: 2, count: 2),
                    Data(repeating: 3, count: 2)
                ]
            ),
            for: url
        )
        defer { BoundedHTTPURLProtocol.unregister(url) }

        await expectBodyTooLarge(
            url: url,
            maximumBytes: 5,
            expectedActualBytes: 6
        )
    }

    @Test
    func cancellationStopsLoadingAndRemainsCancellationError() async throws {
        let url = makeURL("cancellation")
        let probe = BoundedHTTPURLProtocol.LifecycleProbe()
        BoundedHTTPURLProtocol.register(
            .init(
                chunks: [Data(repeating: 1, count: 20)],
                chunkDelayNanoseconds: 1_000_000_000,
                lifecycleProbe: probe
            ),
            for: url
        )
        defer { BoundedHTTPURLProtocol.unregister(url) }

        let client = makeClient()
        let task = Task {
            try await client.execute(
                HTTPRequest(url: url, maximumResponseBodyBytes: 100)
            )
        }

        #expect(await waitUntil { probe.didStart })
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected cancellation")
        } catch is CancellationError {
            // Expected: transport cancellation must not become a generic URL error.
        } catch {
            Issue.record("Expected CancellationError, got \(error)")
        }

        #expect(await waitUntil { probe.didStop })
    }

    @Test
    func declaredContentLengthIsCheckedForEveryResourceProfile() async throws {
        let contract = AppResourceBudgetContract.current
        let profiles = [
            contract.feedXML.body,
            contract.discoveryHTML,
            contract.feedIcon.body,
            contract.articleImage.body,
            contract.opml.body
        ]

        for profile in profiles {
            let url = makeURL("profile-\(profile.input.rawValue)")
            let declaredBytes = profile.maximumCompressedBodyBytes + 1
            BoundedHTTPURLProtocol.register(
                .init(headers: ["Content-Length": "\(declaredBytes)"]),
                for: url
            )

            await expectBodyTooLarge(
                url: url,
                maximumBytes: profile.maximumCompressedBodyBytes,
                expectedActualBytes: declaredBytes
            )
            BoundedHTTPURLProtocol.unregister(url)
        }
    }

    @Test
    func notModifiedIgnoresRepresentationContentLengthAndReturnsEmptyBody() async throws {
        let url = makeURL("not-modified-content-length")
        BoundedHTTPURLProtocol.register(
            .init(
                statusCode: 304,
                headers: ["Content-Length": "1000"]
            ),
            for: url
        )
        defer { BoundedHTTPURLProtocol.unregister(url) }

        let response = try await makeClient().execute(
            HTTPRequest(url: url, maximumResponseBodyBytes: 5)
        )

        #expect(response.statusCode == 304)
        #expect(response.body.isEmpty)
    }

    private func expectBodyTooLarge(
        url: URL,
        maximumBytes: Int64,
        expectedActualBytes: Int64
    ) async {
        do {
            _ = try await makeClient().execute(
                HTTPRequest(
                    url: url,
                    maximumResponseBodyBytes: maximumBytes
                )
            )
            Issue.record("Expected response body limit failure")
        } catch let error as HTTPClientError {
            #expect(
                error == .responseBodyTooLarge(
                    maximumBytes: maximumBytes,
                    actualBytes: expectedActualBytes
                )
            )
        } catch {
            Issue.record("Expected HTTPClientError, got \(error)")
        }
    }

    private func makeClient() -> URLSessionHTTPClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BoundedHTTPURLProtocol.self]
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSessionHTTPClient(configuration: configuration)
    }

    private func makeURL(_ path: String) -> URL {
        URL(string: "https://bounded-http.test/\(path)-\(UUID().uuidString)")!
    }

    private func waitUntil(
        _ condition: @escaping @Sendable () -> Bool
    ) async -> Bool {
        for _ in 0..<200 {
            if condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return condition()
    }
}

private nonisolated final class BoundedHTTPURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated struct Scenario: @unchecked Sendable {
        let statusCode: Int
        let headers: [String: String]
        let chunks: [Data]
        let chunkDelayNanoseconds: UInt64
        let lifecycleProbe: LifecycleProbe?

        init(
            statusCode: Int = 200,
            headers: [String: String] = [:],
            chunks: [Data] = [],
            chunkDelayNanoseconds: UInt64 = 0,
            lifecycleProbe: LifecycleProbe? = nil
        ) {
            self.statusCode = statusCode
            self.headers = headers
            self.chunks = chunks
            self.chunkDelayNanoseconds = chunkDelayNanoseconds
            self.lifecycleProbe = lifecycleProbe
        }
    }

    nonisolated final class LifecycleProbe: @unchecked Sendable {
        private let lock = NSLock()
        private var started = false
        private var stopped = false

        var didStart: Bool {
            lock.lock()
            defer { lock.unlock() }
            return started
        }

        var didStop: Bool {
            lock.lock()
            defer { lock.unlock() }
            return stopped
        }

        func markStarted() {
            lock.lock()
            started = true
            lock.unlock()
        }

        func markStopped() {
            lock.lock()
            stopped = true
            lock.unlock()
        }
    }

    private static let registryLock = NSLock()
    nonisolated(unsafe) private static var scenariosByURL: [URL: Scenario] = [:]

    private let stateLock = NSLock()
    private var deliveryTask: Task<Void, Never>?
    private var stopped = false

    static func register(_ scenario: Scenario, for url: URL) {
        registryLock.lock()
        scenariosByURL[url] = scenario
        registryLock.unlock()
    }

    static func unregister(_ url: URL) {
        registryLock.lock()
        scenariosByURL[url] = nil
        registryLock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let url = request.url else { return false }
        registryLock.lock()
        defer { registryLock.unlock() }
        return scenariosByURL[url] != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url,
              let scenario = Self.scenario(for: url),
              let response = HTTPURLResponse(
                url: url,
                statusCode: scenario.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: scenario.headers
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        scenario.lifecycleProbe?.markStarted()
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)

        let deliveryTask = Task { [weak self] in
            guard let self else { return }

            for chunk in scenario.chunks {
                if scenario.chunkDelayNanoseconds > 0 {
                    do {
                        try await Task.sleep(nanoseconds: scenario.chunkDelayNanoseconds)
                    } catch {
                        return
                    }
                }

                guard self.isStopped == false else { return }
                self.client?.urlProtocol(self, didLoad: chunk)
            }

            guard self.isStopped == false else { return }
            self.client?.urlProtocolDidFinishLoading(self)
        }

        stateLock.lock()
        self.deliveryTask = deliveryTask
        let shouldCancel = stopped
        stateLock.unlock()

        if shouldCancel {
            deliveryTask.cancel()
        }
    }

    override func stopLoading() {
        stateLock.lock()
        stopped = true
        let deliveryTask = self.deliveryTask
        stateLock.unlock()

        deliveryTask?.cancel()
        if let url = request.url {
            Self.scenario(for: url)?.lifecycleProbe?.markStopped()
        }
    }

    private var isStopped: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return stopped
    }

    private static func scenario(for url: URL) -> Scenario? {
        registryLock.lock()
        defer { registryLock.unlock() }
        return scenariosByURL[url]
    }
}
