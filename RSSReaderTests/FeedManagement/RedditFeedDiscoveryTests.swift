import Foundation
import Testing
@testable import RSSReader

@Suite("Feed Management / Reddit Discovery")
@MainActor
struct RedditFeedDiscoveryTests {
    private let feedURL = "https://www.reddit.com/r/apple/.rss"
    private static let atom = """
    <?xml version="1.0" encoding="UTF-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom">
      <id>https://www.reddit.com/r/apple/</id><title>r/apple</title>
      <updated>2026-10-11T10:00:00Z</updated>
      <link href="https://www.reddit.com/r/apple/"/>
    </feed>
    """

    @Test
    func addingRedditFeedUnderUnreadFilterImportsPreviewWithoutRateLimitedSecondRequest() async throws {
        let entries = (1...25).map { index in
            """
            <entry><id>reddit-entry-\(index)</id><title>Article \(index)</title>
            <link href="https://www.reddit.com/r/apple/comments/\(index)/"/>
            <updated>2026-10-11T10:00:00Z</updated><content type="text">Article body</content></entry>
            """
        }.joined()
        let body = Self.atom.replacingOccurrences(of: "</feed>", with: entries + "</feed>")
        let client = ScriptedHTTPClient(steps: [
            .response(statusCode: 200, headers: ["Content-Type": "application/atom+xml", "ETag": "preview-etag"], body: body),
            .response(statusCode: 429, headers: ["x-ratelimit-reset": "30"], body: "")
        ])
        let harness = try TestHarness.make(httpClient: client)
        let appState = AppState()
        appState.selectSidebarArticleFilter(.unread)
        let controller = FeedManagementScreenController()
        controller.handleScenarioSelection(.addFeed, dependencies: harness.dependencies)
        controller.handleAddFeedURLChange("reddit.com/r/apple")
        await controller.handleAddFeedPrimaryAction(dependencies: harness.dependencies, appState: appState)
        #expect(try harness.feedRepository.fetchAllFeeds().isEmpty)
        await controller.handleAddFeedPrimaryAction(dependencies: harness.dependencies, appState: appState)
        let sidebarReloadBeforeCompletion = appState.sidebarReloadID
        await harness.dependencies.appActions.waitForScheduledFeedSaveRefreshes()
        let feed = try #require(try harness.feedRepository.fetchFeed(url: feedURL))
        let snapshot = try #require(harness.dependencies.sidebarQueryService).fetchSnapshot()
        #expect(feed.lastFetchedAt != nil)
        #expect(feed.lastSuccessfulFetchAt != nil)
        #expect(feed.lastSyncError == nil)
        #expect(feed.lastETag == "preview-etag")
        #expect(snapshot.feeds.first { $0.id == feed.id }?.unreadCount == 25)
        #expect(try harness.articleRepository.fetchArticles(feedID: feed.id).count == 25)
        #expect(appState.selectedSidebarArticleFilter == .unread)
        #expect(appState.sidebarReloadID != sidebarReloadBeforeCompletion)
        #expect(await client.recordedRequests().map(\.url.absoluteString) == [feedURL])
    }

    @Test
    func initialRefreshIsScheduledButFailsWhenPreviewIsFollowedByRateLimitedDownload() async throws {
        let client = ScriptedHTTPClient(steps: [
            .response(statusCode: 200, headers: ["Content-Type": "application/atom+xml"], body: Self.atom),
            .response(statusCode: 429, headers: ["x-ratelimit-reset": "30"], body: "")
        ])
        let harness = try TestHarness.make(httpClient: client)
        let service = try #require(harness.dependencies.feedManagementService)
        let preview = try await service.previewFeed(urlString: "reddit.com/r/apple")
        let created = try service.createFeed(.init(preview: preview, folderPlacement: .ungrouped))
        let appState = AppState()
        appState.selectSidebarArticleFilter(.unread)
        // Reproduce the former app boundary, which discarded the preview payload.
        _ = await harness.dependencies.appActions.completeFeedManagementFeedSave(id: created.id, using: appState, selectsSavedFeed: false)
        await harness.dependencies.appActions.waitForScheduledFeedSaveRefreshes()
        let feed = try #require(try harness.feedRepository.fetchFeed(id: created.id))
        #expect(feed.lastFetchedAt != nil)
        #expect(feed.lastSuccessfulFetchAt == nil)
        #expect(feed.lastSyncError?.contains("rateLimited") == true)
        #expect(try harness.articleRepository.fetchArticles(feedID: feed.id).isEmpty)
        #expect(try harness.feedFetchLogRepository.fetchLogs(feedID: feed.id).first?.httpCode == 429)
        #expect(await client.recordedRequests().count == 2)
    }

    @Test
    func initialPreviewSnapshotIsFreshBoundedAndOnlyUsedBeforeFirstSuccess() async throws {
        let now = Date.now
        let url = URL(string: feedURL)!
        let request = FeedRequest(feedID: UUID(), url: url)
        let response = FeedResponse(request: request, sourceURL: url, statusCode: 200, headers: ["Content-Type": "application/atom+xml", "Set-Cookie": "secret"], body: Data(Self.atom.utf8))
        let fresh = FeedInitialFetchSnapshot(response: response, receivedAt: now)
        #expect(fresh.headers["set-cookie"] == nil)
        #expect(fresh.response(for: request, now: now.addingTimeInterval(120)) != nil)
        #expect(fresh.response(for: request, now: now.addingTimeInterval(121)) == nil)
        #expect(fresh.response(for: request, now: now.addingTimeInterval(-1)) == nil)
        #expect(fresh.response(for: FeedRequest(feedID: UUID(), url: URL(string: "https://example.com/feed")!), now: now) == nil)
        let expired = FeedInitialFetchSnapshot(response: response, receivedAt: now.addingTimeInterval(-121))
        let client = ScriptedHTTPClient(steps: [
            .response(statusCode: 200, headers: ["Content-Type": "application/atom+xml"], body: Self.atom),
            .response(statusCode: 304, headers: [:], body: "")
        ])
        let harness = try TestHarness.make(httpClient: client)
        let feed = try #require(harness.insertFeeds(urls: [feedURL]).first)
        let first = await harness.dependencies.appActions.refreshFeed(id: feed.id, initialFetchSnapshot: expired)
        #expect(first?.status == .fetched)
        let second = await harness.dependencies.appActions.refreshFeed(id: feed.id, initialFetchSnapshot: fresh)
        #expect(second?.status == .notModified)
        #expect(await client.recordedRequests().count == 2)
    }

    @Test
    func seededInitialRefreshPreservesCancellationRollbackAndRetry() async throws {
        let client = ScriptedHTTPClient()
        let harness = try TestHarness.make(httpClient: client)
        let feed = try #require(harness.insertFeeds(urls: [feedURL]).first)
        let originalTitle = feed.title
        let body = Self.atom.replacingOccurrences(of: "</feed>", with: """
        <entry><id>seeded-entry</id><title>Seeded Article</title>
        <link href="https://www.reddit.com/r/apple/comments/seeded/"/>
        <updated>2026-10-11T10:00:00Z</updated><content type="text">Body</content></entry></feed>
        """)
        let request = FeedRequest(feedID: feed.id, url: URL(string: feedURL)!)
        let snapshot = FeedInitialFetchSnapshot(response: FeedResponse(
            request: request, sourceURL: request.url, statusCode: 200,
            headers: ["Content-Type": "application/atom+xml", "ETag": "seeded-etag"], body: Data(body.utf8)
        ))
        var cancelsSave = true
        let service = FeedRefreshService(
            logger: TestLogger(), feedFetcher: FeedFetcher(httpClient: client),
            feedRepository: harness.feedRepository, articleRepository: harness.articleRepository,
            feedFetchLogRepository: harness.feedFetchLogRepository,
            cancellationCheckpoint: { checkpoint in
                if checkpoint == .beforeFetchedSave && cancelsSave { throw CancellationError() }
            }
        )
        let cancelled = await service.refresh(feedID: feed.id, initialFetchSnapshot: snapshot)
        #expect(cancelled.status == .cancelled)
        #expect(try harness.articleRepository.fetchArticles(feedID: feed.id).isEmpty)
        let afterCancellation = try #require(try harness.feedRepository.fetchFeed(id: feed.id))
        #expect(afterCancellation.title == originalTitle)
        #expect(afterCancellation.lastETag == "\"etag-old\"")
        #expect(afterCancellation.lastSuccessfulFetchAt == nil)
        #expect(service.inFlightRefreshTasks.isEmpty)
        cancelsSave = false
        let completed = await service.refresh(feedID: feed.id, initialFetchSnapshot: snapshot)
        #expect(completed.status == .fetched)
        #expect(try harness.articleRepository.fetchArticles(feedID: feed.id).count == 1)
        #expect(await client.recordedRequests().isEmpty)
        #expect(service.inFlightRefreshTasks.isEmpty)
    }

    @Test(arguments: [
        "reddit.com/r/apple", "reddit.com/r/apple/", "www.reddit.com/r/apple",
        "https://reddit.com/r/apple", "https://www.reddit.com/r/apple/",
        "http://reddit.com/r/apple", "http://www.reddit.com/r/apple/",
        "old.reddit.com/r/apple", "HTTPS://WWW.REDDIT.COM/r/apple/#top"
    ])
    func subredditVariantsUseAtomWithoutReadingBlockedHTML(_ input: String) async throws {
        let client = ScriptedHTTPClient(responsesByURL: [
            feedURL: .response(statusCode: 200, headers: ["Content-Type": "application/atom+xml"], body: Self.atom),
            "https://www.reddit.com/r/apple/": .response(statusCode: 403, headers: [:], body: "Blocked")
        ])
        let harness = try TestHarness.make(httpClient: client)
        let service = try #require(harness.dependencies.feedManagementService)
        let preview = try await service.previewFeed(urlString: input)
        #expect(preview.requestedURL == feedURL)
        #expect(preview.kind == .atom)
        #expect(preview.title == "r/apple")
        #expect(await client.recordedRequests().map(\.url.absoluteString) == [feedURL])
    }

    @Test(arguments: [
        "https://reddit.com.evil.test/r/apple", "https://evilreddit.com/r/apple",
        "https://reddit.com@evil.test/r/apple", "https://www.reddit.com:444/r/apple",
        "https://www.reddit.com/r/apple/new", "https://www.reddit.com/user/apple",
        "https://www.reddit.com/r/apple?sort=new", "https://www.reddit.com/r/apple/comments/id",
        "https://www.reddit.com/r/apple+swift", "https://example.com/r/apple"
    ])
    func unrelatedHostsAndUnsupportedRoutesKeepGenericDiscovery(_ input: String) throws {
        let plan = try FeedManagementFeedDiscoveryPlanner.makePlan(for: input)
        #expect(plan.preferredFeedURL == nil)
        #expect(plan.feedURLs == [URL(string: input)!])
        #expect(plan.siteURLs.contains(URL(string: input)!))
    }

    @Test(arguments: ["reddit.com/r/apple/.rss", "https://old.reddit.com/r/apple/.rss?limit=10"])
    func directRedditFeedRemainsDirect(_ input: String) throws {
        let plan = try FeedManagementFeedDiscoveryPlanner.makePlan(for: input)
        #expect(plan.feedURLs == [URL(string: plan.displayURL)!])
        #expect(plan.siteURLs.isEmpty)
        #expect(plan.fallbackFeedURLs.isEmpty)
    }

    @Test
    func rateLimitStopsPreviewAndAllowsUserRetry() async throws {
        let logger = RecordingLogger()
        let client = ScriptedHTTPClient(responseSequencesByURL: [feedURL: [
            .response(statusCode: 429, headers: ["X-Ratelimit-Reset": "30"], body: ""),
            .response(statusCode: 200, headers: ["Content-Type": "application/atom+xml"], body: Self.atom)
        ]])
        let harness = try TestHarness.make(httpClient: client, logger: logger)
        let service = try #require(harness.dependencies.feedManagementService)
        let before = Date.now
        do {
            _ = try await service.previewFeed(urlString: "reddit.com/r/apple")
            Issue.record("Expected rate limit")
        } catch let error as FeedFetchError {
            guard case .rateLimited(let retryAt, let responseURL) = error else {
                Issue.record("Expected typed rate limit"); return
            }
            #expect(responseURL == feedURL)
            #expect(try #require(retryAt) >= before.addingTimeInterval(30))
        }
        #expect(await client.recordedRequests().count == 1)
        #expect(logger.contains("stage=direct"))
        #expect(logger.contains("status=429"))
        #expect(try await service.previewFeed(urlString: "reddit.com/r/apple").kind == .atom)
        #expect(await client.recordedRequests().count == 2)
    }

    @Test
    func preservesPreferredAtomFailureInsteadOfLaterFallbackFailure() async throws {
        let client = ScriptedHTTPClient(steps: [
            .response(statusCode: 403, headers: [:], body: "Blocked")
        ] + Array(repeating: .response(statusCode: 404, headers: [:], body: ""), count: 12))
        let harness = try TestHarness.make(httpClient: client)
        let service = try #require(harness.dependencies.feedManagementService)
        do {
            _ = try await service.previewFeed(urlString: "reddit.com/r/apple")
            Issue.record("Expected denied access")
        } catch let error as FeedFetchError {
            #expect(error == .invalidStatusCode(403, responseURL: feedURL))
        }
    }

    @Test
    func htmlRateLimitStopsOriginAndHTTPFallbackRequests() async throws {
        let client = ScriptedHTTPClient(steps: [
            .response(statusCode: 404, headers: [:], body: ""),
            .response(statusCode: 429, headers: ["Retry-After": "20"], body: "")
        ])
        let harness = try TestHarness.make(httpClient: client)
        let service = try #require(harness.dependencies.feedManagementService)
        do {
            _ = try await service.previewFeed(urlString: "https://www.reddit.com/r/apple/new")
            Issue.record("Expected HTML rate limit")
        } catch let error as FeedFetchError {
            #expect(error.httpStatusCode == 429)
        }
        #expect(await client.recordedRequests().count == 2)
    }

    @Test
    func canonicalAtomCancellationDoesNotStartFallback() async throws {
        let client = ScriptedHTTPClient(steps: [.cancelled])
        let harness = try TestHarness.make(httpClient: client)
        let service = try #require(harness.dependencies.feedManagementService)
        await #expect(throws: CancellationError.self) {
            try await service.previewFeed(urlString: "reddit.com/r/apple")
        }
        #expect(await client.recordedRequests().map(\.url.absoluteString) == [feedURL])
    }

    @Test
    func redirectResolvedURLDetectsExistingFeedAndRedactsDiagnostics() async throws {
        let requestedURL = "https://user:secret@example.com/feed.xml?token=sensitive#private"
        let finalURL = "https://www.reddit.com/r/apple/.rss?token=sensitive#private"
        let logger = RecordingLogger()
        let client = DiscoveryRedirectHTTPClient(finalURL: URL(string: finalURL)!, body: Self.atom)
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient(), logger: logger)
        let existing = try #require(harness.insertFeeds(urls: [finalURL]).first)
        let service = DefaultFeedManagementService(
            logger: logger, httpClient: client,
            feedFetcher: FeedFetcher(httpClient: client, retryPolicy: FeedRetryPolicy(maxAttempts: 1)),
            feedRepository: harness.feedRepository, folderRepository: harness.folderRepository,
            articleRepository: harness.articleRepository
        )
        let preview = try await service.previewFeed(urlString: requestedURL)
        #expect(preview.resolvedFeedURL == finalURL)
        #expect(preview.existingFeedID == existing.id)
        #expect(logger.contains("requested=https://example.com/feed.xml final=\(feedURL) status=200"))
        for entry in logger.entries {
            #expect(!entry.message.contains("secret"))
            #expect(!entry.message.contains("sensitive"))
            #expect(!entry.message.contains("private"))
            #expect(!entry.message.contains("<?xml"))
        }
    }

    @Test
    func statusMapperDistinguishesDeniedRateLimitAndMissingFeed() {
        let denied = FeedManagementScreenStatusMapper.addFeedPreviewFailureStatus(for: FeedFetchError.invalidStatusCode(403))
        let limited = FeedManagementScreenStatusMapper.addFeedPreviewFailureStatus(for: FeedFetchError.rateLimited(retryAt: nil))
        let retryAt = Date(timeIntervalSince1970: 1_791_712_800)
        let timed = FeedManagementScreenStatusMapper.addFeedPreviewFailureStatus(for: FeedFetchError.rateLimited(retryAt: retryAt))
        let missing = FeedManagementScreenStatusMapper.addFeedPreviewFailureStatus(for: FeedManagementServiceError.feedDiscoveryFailed("example.com"))
        #expect(Set([denied.title, limited.title, missing.title]).count == 3)
        #expect(denied.showsAlternativeAddressFooter)
        #expect(!limited.showsAlternativeAddressFooter)
        #expect(timed.detail?.contains(retryAt.formatted(date: .abbreviated, time: .standard)) == true)
        #expect(timed.detail?.contains("%@") == false)
    }
}

private actor DiscoveryRedirectHTTPClient: HTTPClient {
    let finalURL: URL
    let body: String
    init(finalURL: URL, body: String) { self.finalURL = finalURL; self.body = body }
    func execute(_ request: HTTPRequest) async throws -> HTTPResponse {
        HTTPResponse(url: finalURL, statusCode: 200, headers: ["Content-Type": "application/atom+xml"], body: Data(body.utf8))
    }
}
