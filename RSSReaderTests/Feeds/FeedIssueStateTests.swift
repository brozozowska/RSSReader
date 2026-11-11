import Foundation
import Testing
@testable import RSSReader

@Suite("Feeds / Active Issues")
@MainActor
struct FeedIssueStateTests {
    @Test
    func initialBackgroundAndScopedRetryShareIssuesAcrossSelections() async throws {
        let firstURL = "https://example.com/first.xml"
        let secondURL = "https://example.com/second.xml"
        let client = ScriptedHTTPClient(responseSequencesByURL: [
            firstURL: [
                .response(statusCode: 403, headers: [:], body: ""),
                .response(statusCode: 429, headers: ["Retry-After": "120"], body: ""),
                .response(statusCode: 304, headers: [:], body: "")
            ],
            secondURL: [
                .response(statusCode: 429, headers: ["Retry-After": "invalid"], body: ""),
                .response(
                    statusCode: 200,
                    headers: ["Content-Type": "application/rss+xml"],
                    body: makeValidRSSFeedXML(
                        channelTitle: "Recovered",
                        channelLink: "https://example.com/",
                        language: "en",
                        itemTitle: "Recovered article",
                        itemLink: "https://example.com/article",
                        itemGUID: "recovered",
                        itemDescription: "Recovered",
                        pubDate: "Tue, 02 Jan 2024 10:00:00 GMT"
                    )
                )
            ]
        ])
        let harness = try TestHarness.make(httpClient: client)
        let first = Feed(url: firstURL, title: "First", lastSyncError: "legacy marker")
        let second = Feed(url: secondURL, title: "Second")
        try harness.feedRepository.insert(first)
        try harness.feedRepository.insert(second)
        let dependencies = harness.dependencies
        let issues = dependencies.feedIssues
        let actions = dependencies.appActions
        #expect(issues.issues.isEmpty)

        let initial = try #require(await actions.refreshFeed(id: first.id))
        #expect(initial.failureReason == .httpStatus(403, retryAt: nil))
        #expect(issues.issues[.feed(first.id)]?.attemptedAt == initial.startedAt)

        let settings = try #require(dependencies.appSettingsService)
        _ = try settings.updateSettings(AppSettingsPatch(refreshIntervalPreference: .hourly))
        let background = await actions.refreshFeedsForBackground()
        guard case .executed(let result) = background else {
            Issue.record("Expected scheduled refresh")
            return
        }
        #expect(result.summary.failedCount == 2)
        #expect(issues.issues.count == 2)
        let rateLimited = try #require(result.batchResult.results.first { $0.feedID == first.id })
        let retryAt = try #require(issues.issues[.feed(first.id)]?.retryAt)
        #expect(rateLimited.failureReason == .httpStatus(429, retryAt: retryAt))
        #expect(issues.issues[.feed(first.id)]?.reason == rateLimited.failureReason)
        #expect(retryAt >= rateLimited.startedAt.addingTimeInterval(120))
        #expect(retryAt <= rateLimited.finishedAt.addingTimeInterval(120))
        #expect(issues.issues[.feed(second.id)]?.reason == .httpStatus(429, retryAt: nil))

        let appState = AppState()
        let firstRetry = await actions.retryFeedIssue(.feed(first.id), using: appState)
        #expect(firstRetry?.targetFeedIDs == [first.id])
        #expect(firstRetry?.summary.notModifiedCount == 1)
        #expect(issues.issues[.feed(first.id)] == nil)
        #expect(issues.issues[.feed(second.id)] != nil)

        let secondRetry = await actions.retryFeedIssue(.feed(second.id), using: appState)
        #expect(secondRetry?.summary.fetchedCount == 1)
        #expect(issues.issues.isEmpty)
        #expect(try settings.fetchSettings().lastFeedsRefreshAt == nil)
    }

    @Test
    func failureClassificationDiscardsDiagnosticDetails() {
        #expect(FeedRefreshFailureReason(error: FeedFetchError.rateLimited(
            retryAt: nil, responseURL: "https://example.com/private"
        )) == .httpStatus(429, retryAt: nil))
        #expect(FeedRefreshFailureReason(error: FeedParserError.emptyDocument) == .invalidFeed)
        #expect(FeedRefreshFailureReason(error: FeedFetchError.unsupportedContentType("text/html")) == .unsupportedFeed)
        #expect(FeedRefreshFailureReason(error: FeedParserError.malformedXML(
            line: 1, column: 1, message: "private response fragment"
        )) == .parserFailure)
    }

    @Test
    func staleDuplicateAndCancelledCompletionsPreserveCurrentIssue() {
        let state = FeedIssueState()
        let target = FeedIssue.Target.feed(UUID())
        let first = state.begin(target)
        let current = state.begin(target)
        state.finish(target, token: current, attemptedAt: .distantFuture, reason: .timeout)
        state.finish(target, token: first, attemptedAt: .distantPast, reason: nil)
        state.finish(target, token: current, attemptedAt: .distantPast, reason: .transport)
        let cancelled = state.begin(target)
        state.finish(target, token: cancelled, attemptedAt: .distantPast, reason: nil, cancelled: true)

        #expect(state.issues[target]?.reason == .timeout)
        #expect(state.issues[target]?.attemptedAt == .distantFuture)
    }

    @Test
    func scheduledInitialRefreshPublishesAfterSelectionChanges() async throws {
        let url = "https://example.com/initial.xml"
        let gate = ScriptedHTTPClientResponseGate()
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient(responsesByURL: [
            url: .gatedResponse(statusCode: 403, headers: [:], body: "", gate: gate)
        ]))
        let feed = try #require(try harness.insertFeeds(urls: [url]).first)
        let appState = AppState()
        let dependencies = harness.dependencies

        dependencies.appActions.completeFeedManagementFeedSave(
            id: feed.id,
            using: appState,
            selectsSavedFeed: true
        )
        try await waitUntil("initial refresh entered") { await gate.hasEntered() }
        appState.selectSidebarSelection(.starred)
        await gate.release()
        try await waitUntil("initial refresh published") {
            dependencies.feedIssues.issues[.feed(feed.id)]?.reason == .httpStatus(403, retryAt: nil)
        }

        #expect(appState.selectedSidebarSelection == .starred)
    }

    @Test
    func cancelledExecutionDoesNotReplaceAnExistingIssue() async throws {
        let url = "https://example.com/cancelled.xml"
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient(responseSequencesByURL: [
            url: [.urlError(.timedOut), .cancelled]
        ]))
        let feed = try #require(try harness.insertFeeds(urls: [url]).first)
        let service = try #require(harness.dependencies.feedRefreshService)
        let issues = harness.dependencies.feedIssues

        let failed = await service.refresh(feedID: feed.id)
        let cancelled = await service.refresh(feedID: feed.id)

        #expect(cancelled.status == .cancelled)
        #expect(issues.issues[.feed(feed.id)]?.reason == .timeout)
        #expect(issues.issues[.feed(feed.id)]?.attemptedAt == failed.startedAt)
    }

    @Test
    func unsubscribeOnlyClearsAfterSuccessAndLateRefreshCannotRecreateIssue() async throws {
        let url = "https://example.com/unsubscribe.xml"
        let gate = ScriptedHTTPClientResponseGate()
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient(responseSequencesByURL: [
            url: [
                .urlError(.timedOut),
                .gatedResponse(statusCode: 403, headers: [:], body: "", gate: gate)
            ]
        ]))
        let feed = try #require(try harness.insertFeeds(urls: [url]).first)
        let feedID = feed.id
        let actions = harness.dependencies.appActions
        let state = AppState()
        let issues = harness.dependencies.feedIssues
        _ = await actions.refreshFeed(id: feedID)
        #expect(issues.issues[.feed(feedID)]?.reason == .timeout)

        actions.requestFeedUnsubscribeConfirmation(id: feedID, title: feed.title, using: state)
        actions.cancelFeedUnsubscribeConfirmation(using: state)
        #expect(issues.issues[.feed(feedID)]?.reason == .timeout)

        let unavailable = AppDependencies(logger: TestLogger())
        let unavailableActions = FeedManagementDestructiveActions(
            logger: TestLogger(),
            folderRepository: nil,
            feedManagementService: unavailable.feedManagementService,
            feedIssues: issues,
            scheduleUnreadAppIconBadgeRefresh: {}
        )
        unavailableActions.unsubscribeFeed(id: feedID, using: state)
        #expect(issues.issues[.feed(feedID)]?.reason == .timeout)

        let refresh = Task { await actions.refreshFeed(id: feedID) }
        defer { refresh.cancel() }
        try await waitUntil("HTTP response gate entry") { await gate.hasEntered() }
        actions.requestFeedUnsubscribeConfirmation(id: feedID, title: feed.title, using: state)
        actions.confirmPendingFeedUnsubscribe(using: state)
        #expect(issues.issues[.feed(feedID)] == nil)
        await gate.release()
        _ = await refresh.value
        #expect(issues.issues[.feed(feedID)] == nil)
        #expect(try harness.fetchFeed(id: feedID) == nil)
    }

    @Test(arguments: [false, true])
    func operationRetryUsesOriginalFolderOrFailedTargets(failedOnly: Bool) async throws {
        let firstURL = "https://example.com/folder-first.xml"
        let secondURL = "https://example.com/folder-second.xml"
        let unrelatedURL = "https://example.com/unrelated.xml"
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient(responsesByURL: [
            firstURL: .response(statusCode: 304, headers: [:], body: ""),
            secondURL: .response(statusCode: 304, headers: [:], body: "")
        ]))
        let feeds = try harness.insertFeeds(urls: [firstURL, secondURL, unrelatedURL])
        let folder = Folder(name: "News")
        feeds[0].folder = folder
        feeds[1].folder = folder
        try harness.saveModelContext()

        let scope = ManualFeedRefreshScope.folder("News")
        let target = FeedIssue.Target.operation(failedOnly ? .failedFeeds(scope) : .selection(scope))
        let issues = harness.dependencies.feedIssues
        let token = issues.begin(target)
        issues.finish(
            target, token: token, attemptedAt: .distantPast, reason: .infrastructure,
            retryFeedIDs: failedOnly ? [feeds[0].id] : []
        )

        let appState = AppState()
        appState.selectSidebarSelection(.starred)
        let result = try #require(await harness.dependencies.appActions.retryFeedIssue(target, using: appState))
        let expectedIDs = failedOnly ? [feeds[0].id] : [feeds[0].id, feeds[1].id]
        #expect(Set(result.targetFeedIDs) == Set(expectedIDs))
        #expect(result.isCompleteSuccess)
        #expect(issues.issues[target] == nil)
        #expect(appState.selectedSidebarSelection == .starred)
        let settings = try #require(harness.dependencies.appSettingsService)
        #expect(try settings.fetchSettings().lastFeedsRefreshAt == nil)
    }

    @Test(arguments: [SidebarSelection.inbox, .folder("News")])
    func unavailableRefreshProducesAnOperationIssue(selection: SidebarSelection) async throws {
        let dependencies = AppDependencies(logger: TestLogger())
        let context = ManualFeedRefreshContext(selection: selection, sidebarArticleFilter: .allItems)
        let appState = AppState()
        let state = dependencies.feedIssues
        let unrelated = FeedIssue.Target.feed(UUID())
        let token = state.begin(unrelated)
        state.finish(unrelated, token: token, attemptedAt: .distantPast, reason: .timeout)
        let result = try #require(await dependencies.appActions.refreshSelection(context, using: appState))
        let target = FeedIssue.Target.operation(.selection(context.scope))

        #expect(result.batchFailureReason == .infrastructure)
        #expect(result.results.isEmpty)
        #expect(!result.isCompleteSuccess)
        #expect(state.issues[target]?.reason == .infrastructure)
        #expect(state.issues[target]?.canRetry == false)
        let retry = await dependencies.appActions.retryFeedIssue(target, using: appState)
        #expect(retry == nil)
        #expect(state.issues[target]?.reason == .infrastructure)
        #expect(state.issues[unrelated]?.reason == .timeout)
    }
}
