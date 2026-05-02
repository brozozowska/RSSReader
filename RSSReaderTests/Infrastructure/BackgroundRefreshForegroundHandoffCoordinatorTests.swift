import Foundation
import Testing
@testable import RSSReader

@MainActor
@Suite("Infrastructure / Background Refresh Foreground Handoff Coordinator")
struct BackgroundRefreshForegroundHandoffCoordinatorTests {
    @Test
    func backgroundRefreshForegroundHandoffCoordinatorRequestsReloadImmediatelyWhenRuntimeIsActive() {
        let coordinator = DefaultBackgroundRefreshForegroundHandoffCoordinator()
        let recorder = ReloadRecorder()

        coordinator.bindReloadHandler {
            recorder.recordReload()
        }
        coordinator.updateRuntimeState(.activeForeground)

        coordinator.handleBackgroundRefreshExecutionOutcome(.success(makeBackgroundResult(fetchedCount: 2)))

        #expect(recorder.reloadCount == 1)
    }

    @Test
    func backgroundRefreshForegroundHandoffCoordinatorDefersReloadUntilRuntimeBecomesActive() {
        let coordinator = DefaultBackgroundRefreshForegroundHandoffCoordinator()
        let recorder = ReloadRecorder()

        coordinator.bindReloadHandler {
            recorder.recordReload()
        }
        coordinator.updateRuntimeState(.inactiveOrBackground)

        coordinator.handleBackgroundRefreshExecutionOutcome(.success(makeBackgroundResult(fetchedCount: 1)))
        #expect(recorder.reloadCount == 0)

        coordinator.updateRuntimeState(.activeForeground)
        #expect(recorder.reloadCount == 1)
    }

    @Test
    func backgroundRefreshForegroundHandoffCoordinatorCoalescesDeferredReloadsIntoSingleForegroundDelivery() {
        let coordinator = DefaultBackgroundRefreshForegroundHandoffCoordinator()
        let recorder = ReloadRecorder()

        coordinator.bindReloadHandler {
            recorder.recordReload()
        }
        coordinator.updateRuntimeState(.inactiveOrBackground)

        coordinator.handleBackgroundRefreshExecutionOutcome(.success(makeBackgroundResult(fetchedCount: 1)))
        coordinator.handleBackgroundRefreshExecutionOutcome(.partialFailure(makeBackgroundResult(fetchedCount: 3)))

        #expect(recorder.reloadCount == 0)

        coordinator.updateRuntimeState(.activeForeground)
        #expect(recorder.reloadCount == 1)
    }

    @Test
    func backgroundRefreshForegroundHandoffCoordinatorDoesNotRequestReloadForNonMaterializingOutcome() {
        let coordinator = DefaultBackgroundRefreshForegroundHandoffCoordinator()
        let recorder = ReloadRecorder()

        coordinator.bindReloadHandler {
            recorder.recordReload()
        }
        coordinator.updateRuntimeState(.activeForeground)

        coordinator.handleBackgroundRefreshExecutionOutcome(.totalFailure(makeBackgroundResult(fetchedCount: 0)))

        #expect(recorder.reloadCount == 0)
    }

    private func makeBackgroundResult(
        fetchedCount: Int
    ) -> BackgroundFeedRefreshResult {
        let startedAt = Date(timeIntervalSince1970: 0)
        let results = (0..<fetchedCount).map { index in
            FeedRefreshResult.fetched(
                feedID: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!,
                startedAt: startedAt,
                finishedAt: startedAt,
                processedEntryCount: 1,
                upsertedEntryCount: 1,
                rejectedEntryCount: 0
            )
        }

        return BackgroundFeedRefreshResult(
            batchResult: FeedRefreshBatchResult(
                startedAt: startedAt,
                finishedAt: startedAt,
                results: results
            )
        )
    }
}

@MainActor
private final class ReloadRecorder {
    private(set) var reloadCount = 0

    func recordReload() {
        reloadCount += 1
    }
}
