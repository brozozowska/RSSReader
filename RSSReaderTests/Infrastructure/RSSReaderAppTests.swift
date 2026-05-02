import Foundation
import Testing
@testable import RSSReader

@Suite("Infrastructure / RSSReaderApp")
@MainActor
struct RSSReaderAppTests {
    @Test
    func rssReaderAppUsesBackgroundRefreshIdentifierFromInfrastructureConfiguration() {
        #expect(
            RSSReaderApp.backgroundAppRefreshIdentifier
                == BackgroundRefreshTaskConfiguration.appRefreshIdentifier
        )
    }

    @Test
    func performBackgroundAppRefreshDelegatesToBackgroundRefreshServiceThroughAppDependencies() async {
        let expectedResult = BackgroundFeedRefreshResult(
            batchResult: FeedRefreshBatchResult(
                startedAt: .distantPast,
                finishedAt: .distantPast.addingTimeInterval(1),
                results: []
            )
        )
        let backgroundRefreshService = BackgroundRefreshServiceSpy(result: expectedResult)
        let dependencies = AppDependencies(
            logger: TestLogger(),
            backgroundRefreshService: backgroundRefreshService
        )

        let outcome = await performBackgroundAppRefresh(using: dependencies)

        #expect(backgroundRefreshService.performScheduledRefreshCallCount == 1)
        switch outcome {
        case .success(let result):
            #expect(result.trigger == .background)
            #expect(result.batchResult.results.isEmpty == true)
            #expect(result.duration == 1)
        case .partialFailure, .totalFailure, .skippedManual, .failedToStart, .cancelled:
            Issue.record("Expected success execution outcome")
        }
    }
}

@MainActor
private final class BackgroundRefreshServiceSpy: BackgroundRefreshService {
    private(set) var performScheduledRefreshCallCount = 0
    private let result: BackgroundFeedRefreshResult?

    init(result: BackgroundFeedRefreshResult?) {
        self.result = result
    }

    func loadConfiguration() throws -> BackgroundRefreshConfiguration {
        Issue.record("loadConfiguration() should not be used in this test")
        throw BackgroundRefreshServiceSpyError.unexpectedInvocation
    }

    func updatePreference(
        _ preference: RefreshPreference,
        updatedAt: Date
    ) throws -> BackgroundRefreshConfiguration {
        Issue.record("updatePreference(_:updatedAt:) should not be used in this test")
        throw BackgroundRefreshServiceSpyError.unexpectedInvocation
    }

    func performScheduledRefresh() async -> BackgroundRefreshServiceExecutionResult {
        performScheduledRefreshCallCount += 1
        return .executed(result!)
    }
}

private enum BackgroundRefreshServiceSpyError: Error {
    case unexpectedInvocation
}
