import Foundation
import Testing
@testable import RSSReader

@Suite("Feed Management / Save Refresh Ownership")
@MainActor
struct FeedSaveRefreshSchedulerTests {
    @Test
    func pendingSaveKeepsFirstSnapshotAndAllWaitersAwaitCompletion() async throws {
        let scheduler = FeedSaveRefreshScheduler()
        let appState = AppState()
        let feedID = UUID()
        let request = FeedRequest(feedID: feedID, url: URL(string: "https://example.com/seed")!)
        let snapshot = FeedInitialFetchSnapshot(response: FeedResponse(
            request: request, sourceURL: request.url, statusCode: 200,
            headers: ["Content-Type": "application/rss+xml"], body: Data("seed".utf8)
        ))
        let gate = AsyncTestGate()
        defer { gate.release() }
        var receivedSnapshots: [FeedInitialFetchSnapshot?] = []
        var duplicateExecutions = 0
        scheduler.schedule(id: feedID, initialFetchSnapshot: snapshot, using: appState) { id, seed in
            #expect(id == feedID)
            receivedSnapshots.append(seed)
            do { try await gate.wait("scheduled save refresh completion") }
            catch { Issue.record(error) }
        }
        try await waitUntil("refresh entered gate") { gate.waiterCount == 1 }
        appState.selectSidebarSelection(.starred)

        scheduler.schedule(id: feedID, initialFetchSnapshot: nil, using: appState) { _, _ in
            duplicateExecutions += 1
        }
        let sidebarBeforeCompletion = appState.sidebarReloadID
        let articlesBeforeCompletion = appState.articleListReloadID
        var waiterEntries = 0
        var waiterCompletions = 0
        let first = Task { @MainActor in
            waiterEntries += 1
            await scheduler.waitForAll()
            waiterCompletions += 1
        }
        let second = Task { @MainActor in
            waiterEntries += 1
            await scheduler.waitForAll()
            waiterCompletions += 1
        }
        try await waitUntil("both waiters awaiting scheduled work") { waiterEntries == 2 }
        #expect(waiterCompletions == 0)
        #expect(appState.sidebarReloadID == sidebarBeforeCompletion)
        #expect(appState.articleListReloadID == articlesBeforeCompletion)

        gate.release()
        await first.value
        await second.value
        #expect(waiterCompletions == 2)
        #expect(receivedSnapshots == [snapshot])
        #expect(duplicateExecutions == 0)
        #expect(appState.selectedSidebarSelection == .starred)
        #expect(appState.sidebarReloadID != sidebarBeforeCompletion)
        #expect(appState.articleListReloadID != articlesBeforeCompletion)

        // Completed work releases its slot; a later save remains a new refresh.
        scheduler.schedule(id: feedID, initialFetchSnapshot: nil, using: appState) { _, seed in
            receivedSnapshots.append(seed)
        }
        await scheduler.waitForAll()
        #expect(receivedSnapshots == [snapshot, nil])
    }

    @Test
    func waitIncludesAnotherFeedScheduledWhileFirstRefreshIsSuspended() async throws {
        let scheduler = FeedSaveRefreshScheduler()
        let appState = AppState()
        let firstGate = AsyncTestGate()
        let secondGate = AsyncTestGate()
        defer { firstGate.release(); secondGate.release() }
        scheduler.schedule(id: UUID(), initialFetchSnapshot: nil, using: appState) { _, _ in
            do { try await firstGate.wait("first save") }
            catch { Issue.record(error) }
        }
        var didCompleteWait = false
        let waiter = Task { @MainActor in
            await scheduler.waitForAll()
            didCompleteWait = true
        }
        try await waitUntil("first refresh suspended") { firstGate.waiterCount == 1 }
        scheduler.schedule(id: UUID(), initialFetchSnapshot: nil, using: appState) { _, _ in
            do { try await secondGate.wait("second save") }
            catch { Issue.record(error) }
        }
        try await waitUntil("second refresh suspended") { secondGate.waiterCount == 1 }
        firstGate.release()
        #expect(didCompleteWait == false)
        secondGate.release()
        await waiter.value
        #expect(didCompleteWait)
    }

    @Test(arguments: [false, true])
    func failedOrCancelledRefreshCompletesReloadAndReleasesScheduledWork(cancelled: Bool) async throws {
        let url = "https://example.com/save-failure"
        let client = ScriptedHTTPClient(steps: [
            cancelled ? .cancelled : .response(statusCode: 500, headers: [:], body: "")
        ])
        let harness = try TestHarness.make(httpClient: client)
        let feed = try #require(harness.insertFeeds(urls: [url]).first)
        let appState = AppState()
        harness.dependencies.appActions.showFeedManagement(using: appState)

        let result = await harness.dependencies.appActions.finishSavingFeed(id: feed.id, using: appState)
        #expect(result == nil)
        #expect(appState.isPresentingFeedManagementScreen == false)
        #expect(appState.selectedSidebarSelection == .feed(feed.id))
        let sidebarBeforeCompletion = appState.sidebarReloadID
        let articlesBeforeCompletion = appState.articleListReloadID

        // A fresh router value must observe the same dependency-owned continuation.
        await harness.dependencies.appActions.waitForScheduledFeedSaveRefreshes()
        #expect(appState.sidebarReloadID != sidebarBeforeCompletion)
        #expect(appState.articleListReloadID != articlesBeforeCompletion)
        #expect(try harness.articleRepository.fetchArticles(feedID: feed.id).isEmpty)
        #expect(await client.recordedRequests().count == 1)
        let log = try #require(try harness.feedFetchLogRepository.fetchLogs(feedID: feed.id).first)
        #expect(log.status == (cancelled ? "cancelled" : "failed"))
    }

    @Test
    func completionWithoutAppStateDoesNotScheduleRefresh() async throws {
        let client = ScriptedHTTPClient()
        let harness = try TestHarness.make(httpClient: client)
        let result = await harness.dependencies.appActions.completeFeedManagementFeedSave(
            id: UUID(), using: nil, selectsSavedFeed: false
        )
        await harness.dependencies.appActions.waitForScheduledFeedSaveRefreshes()
        #expect(result == nil)
        #expect(await client.recordedRequests().isEmpty)
    }

    @Test
    func cancelledSaveCallerDoesNotCancelIndependentRefresh() async throws {
        let gate = AsyncTestGate()
        defer { gate.release() }
        let scheduler = FeedSaveRefreshScheduler()
        let appState = AppState()
        var executionWasCancelled: Bool?
        let caller = Task { @MainActor in
            do { try await gate.wait("cancel save caller") }
            catch {}
            #expect(Task.isCancelled)
            scheduler.schedule(id: UUID(), initialFetchSnapshot: nil, using: appState) { _, _ in
                executionWasCancelled = Task.isCancelled
            }
        }
        caller.cancel()
        gate.release()
        await caller.value
        await scheduler.waitForAll()
        #expect(executionWasCancelled == false)
    }
}
