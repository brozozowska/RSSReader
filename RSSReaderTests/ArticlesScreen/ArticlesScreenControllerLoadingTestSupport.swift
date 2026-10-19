import Foundation
import SwiftData
import Testing
@testable import RSSReader

@MainActor
final class ArticlesScreenSearchQueryGate {
    let suspendedQuery: String
    let suspendedSnapshot: ArticleSearchResultSnapshot
    let immediateSnapshot: ArticleSearchResultSnapshot
    private(set) var requests: [ArticleSearchRequest] = []
    private let gate = AsyncTestGate()

    init(
        suspendedQuery: String,
        suspendedSnapshot: ArticleSearchResultSnapshot,
        immediateSnapshot: ArticleSearchResultSnapshot
    ) {
        self.suspendedQuery = suspendedQuery
        self.suspendedSnapshot = suspendedSnapshot
        self.immediateSnapshot = immediateSnapshot
    }

    var hasSuspendedRequest: Bool {
        gate.waiterCount > 0
    }

    func execute(_ request: ArticleSearchRequest) async throws -> ArticleSearchResultSnapshot {
        requests.append(request)
        guard request.normalizedQuery == suspendedQuery else {
            return immediateSnapshot
        }

        try await gate.wait("query fixture release", honorsCancellation: false)
        return suspendedSnapshot
    }

    func releaseSuspendedRequest() {
        gate.release()
    }
}

@MainActor
final class ArticlesScreenSelectionQueryGate {
    let suspendedSelection: SidebarSelection
    let immediateSnapshot: ArticleSearchResultSnapshot
    let suspendedSnapshot: ArticleSearchResultSnapshot
    private(set) var requestCount = 0
    private let gate = AsyncTestGate()

    init(
        suspendedSelection: SidebarSelection,
        immediateSnapshot: ArticleSearchResultSnapshot,
        suspendedSnapshot: ArticleSearchResultSnapshot
    ) {
        self.suspendedSelection = suspendedSelection
        self.immediateSnapshot = immediateSnapshot
        self.suspendedSnapshot = suspendedSnapshot
    }

    var hasSuspendedRequest: Bool {
        gate.waiterCount > 0
    }

    func execute(_ request: ArticleSearchRequest) async throws -> ArticleSearchResultSnapshot {
        requestCount += 1
        guard request.selection == suspendedSelection else {
            return immediateSnapshot
        }

        try await gate.wait("query fixture release", honorsCancellation: false)
        return suspendedSnapshot
    }

    func releaseSuspendedRequest() {
        gate.release()
    }
}

@MainActor
final class ArticlesScreenNextPageQueryGate {
    let firstPage: ArticleSearchResultSnapshot
    let nextPage: ArticleSearchResultSnapshot
    private(set) var requests: [ArticleSearchRequest] = []
    private let gate = AsyncTestGate()

    init(
        firstPage: ArticleSearchResultSnapshot,
        nextPage: ArticleSearchResultSnapshot
    ) {
        self.firstPage = firstPage
        self.nextPage = nextPage
    }

    var hasSuspendedRequest: Bool {
        gate.waiterCount > 0
    }

    func execute(_ request: ArticleSearchRequest) async throws -> ArticleSearchResultSnapshot {
        requests.append(request)
        guard request.cursor != nil else { return firstPage }

        try await gate.wait("next page fixture release")
        return nextPage
    }

    func releaseNextPage() {
        gate.release()
    }
}

@MainActor
final class ArticlesScreenStaleNextPageQueryGate {
    let firstPage: ArticleSearchResultSnapshot
    let staleNextPage: ArticleSearchResultSnapshot
    let replacementPage: ArticleSearchResultSnapshot
    private let gate = AsyncTestGate()

    init(
        firstPage: ArticleSearchResultSnapshot,
        staleNextPage: ArticleSearchResultSnapshot,
        replacementPage: ArticleSearchResultSnapshot
    ) {
        self.firstPage = firstPage
        self.staleNextPage = staleNextPage
        self.replacementPage = replacementPage
    }

    var hasSuspendedRequest: Bool {
        gate.waiterCount > 0
    }

    func execute(_ request: ArticleSearchRequest) async throws -> ArticleSearchResultSnapshot {
        if request.cursor != nil {
            try await gate.wait("stale next page release", honorsCancellation: false)
            return staleNextPage
        }
        return request.normalizedQuery.isEmpty ? firstPage : replacementPage
    }

    func releaseStaleNextPage() {
        gate.release()
    }
}

@MainActor
final class ArticlesScreenSearchDebounceGate {
    private(set) var invocationCount = 0
    private let gate = AsyncTestGate()

    var hasSuspendedRequest: Bool {
        gate.waiterCount > 0
    }

    func wait() async throws {
        invocationCount += 1
        guard invocationCount == 1 else { return }

        try await gate.wait("search debounce release")
    }

    func releaseSuspendedRequest() {
        gate.release()
    }
}

@MainActor
final class ArticlesScreenProductionSearchCancellationGate {
    private enum WaitError: Error {
        case progressStreamFinished
        case timedOut
    }

    private let cancelledQuery: String
    private let progressStream: AsyncStream<ArticleSearchScanBatchObservation>
    private let progressContinuation: AsyncStream<ArticleSearchScanBatchObservation>.Continuation
    private var didSignalFirstCancelledBatch = false
    private let cancellationGate = AsyncTestGate()
    private var observations: [ArticleSearchScanBatchObservation] = []

    init(cancelledQuery: String) {
        self.cancelledQuery = cancelledQuery
        let progress = AsyncStream.makeStream(of: ArticleSearchScanBatchObservation.self)
        self.progressStream = progress.stream
        self.progressContinuation = progress.continuation
    }

    var cancelledQueryScannedCandidateCount: Int {
        scannedCandidateCount(for: cancelledQuery)
    }

    var isCancelledQuerySuspended: Bool {
        cancellationGate.waiterCount > 0
    }

    func scannedCandidateCount(for query: String) -> Int {
        observations
            .filter { $0.normalizedQuery == query }
            .reduce(0) { partialResult, observation in
                partialResult + observation.scannedCandidateCount
            }
    }

    func observe(_ observation: ArticleSearchScanBatchObservation) async {
        observations.append(observation)
        guard observation.normalizedQuery == cancelledQuery,
              didSignalFirstCancelledBatch == false else {
            return
        }

        didSignalFirstCancelledBatch = true
        progressContinuation.yield(observation)
        progressContinuation.finish()
        do {
            try await cancellationGate.wait("production search probe release")
        } catch is CancellationError {
            // The production scan checks cancellation after this probe returns.
        } catch {
            Issue.record(error)
        }
    }

    func releaseCancelledQuery() {
        cancellationGate.release()
    }

    func waitForFirstCancelledBatch(
        timeout: Duration = .seconds(5)
    ) async throws -> ArticleSearchScanBatchObservation {
        let progressStream = progressStream
        return try await withThrowingTaskGroup(
            of: ArticleSearchScanBatchObservation.self
        ) { group in
            group.addTask {
                for await observation in progressStream {
                    return observation
                }
                throw WaitError.progressStreamFinished
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw WaitError.timedOut
            }

            defer { group.cancelAll() }
            guard let observation = try await group.next() else {
                throw WaitError.progressStreamFinished
            }
            group.cancelAll()
            return observation
        }
    }
}
