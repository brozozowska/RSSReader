import Foundation
import SwiftData
import Testing
@testable import RSSReader

@Suite("Feeds / Refresh Service / Failure State")
@MainActor
struct FeedRefreshServiceFailureStateTests {
    @Test
    func fetchedFinalSaveFailureRollsBackStagedFeedAndArticleMutations() async throws {
        let feedURL = "https://example.com/fetched-final-save-failure.xml"
        let oldSuccessAt = Date(timeIntervalSince1970: 1_700_000_000)
        let client = ScriptedHTTPClient(
            responsesByURL: [
                feedURL: .response(
                    statusCode: 200,
                    headers: [
                        "Content-Type": "application/rss+xml; charset=utf-8",
                        "ETag": "\"staged-etag\""
                    ],
                    body: makeValidRSSFeedXML(
                        channelTitle: "Staged Feed",
                        channelLink: "https://example.com/staged/",
                        language: "en",
                        itemTitle: "Staged Article",
                        itemLink: "https://example.com/articles/staged",
                        itemGUID: "staged-article",
                        itemDescription: "Staged summary",
                        pubDate: "Tue, 02 Jan 2024 10:00:00 GMT"
                    )
                )
            ]
        )
        let harness = try TestHarness.make(httpClient: client)
        let feed = Feed(
            url: feedURL,
            siteURL: "https://example.com/original/",
            title: "Original Feed",
            lastSuccessfulFetchAt: oldSuccessAt,
            lastETag: "\"original-etag\"",
            lastSyncError: "Previous error"
        )
        try harness.feedRepository.insert(feed)
        let saveProbe = FeedSaveFailureProbe(failingSaveCalls: [2])
        let feedRepository = SwiftDataFeedRepository(
            modelContext: harness.modelContainer.mainContext,
            persistenceSaveOperation: saveProbe.save
        )
        let service = makeService(
            client: client,
            harness: harness,
            feedRepository: feedRepository
        )

        let result = await service.refresh(feedID: feed.id)

        #expect(result.status == .failed)
        #expect(result.errorDescription?.contains("injected_feed_save_failure_call_2") == true)
        #expect(service.inFlightRefreshTasks[feed.id] == nil)
        #expect(saveProbe.saveCallCount == 3)

        let finalSaveSnapshot = try #require(saveProbe.failureSnapshot(for: 2))
        #expect(finalSaveSnapshot.hasChanges)
        #expect(finalSaveSnapshot.feedTitle == "Staged Feed")
        #expect(finalSaveSnapshot.lastETag == "\"staged-etag\"")
        #expect(finalSaveSnapshot.insertedArticleTitles == ["Staged Article"])

        let persistedFeed = try #require(try feedRepository.fetchFeed(id: feed.id))
        #expect(persistedFeed.siteURL == "https://example.com/original/")
        #expect(persistedFeed.title == "Original Feed")
        #expect(persistedFeed.lastFetchedAt != nil)
        #expect(persistedFeed.lastSuccessfulFetchAt == oldSuccessAt)
        #expect(persistedFeed.lastETag == "\"original-etag\"")
        #expect(persistedFeed.lastSyncError?.contains("injected_feed_save_failure_call_2") == true)
        #expect(try harness.articleRepository.fetchArticles(feedID: feed.id).isEmpty)
        #expect(harness.modelContainer.mainContext.hasChanges == false)

        let log = try #require(try harness.feedFetchLogRepository.fetchLatestLog(feedID: feed.id))
        #expect(log.status == "failed")
        #expect(log.message?.contains("injected_feed_save_failure_call_2") == true)
    }

    @Test
    func notModifiedFinalSaveFailureRollsBackStagedMetadataMutations() async throws {
        let feedURL = "https://example.com/not-modified-final-save-failure.xml"
        let oldSuccessAt = Date(timeIntervalSince1970: 1_700_000_000)
        let client = ScriptedHTTPClient(
            responsesByURL: [
                feedURL: .response(
                    statusCode: 304,
                    headers: [
                        "ETag": "\"staged-etag\"",
                        "Last-Modified": "Wed, 03 Jan 2024 12:00:00 GMT"
                    ],
                    body: ""
                )
            ]
        )
        let harness = try TestHarness.make(httpClient: client)
        let feed = Feed(
            url: feedURL,
            title: "Stable Feed",
            lastSuccessfulFetchAt: oldSuccessAt,
            lastETag: "\"original-etag\"",
            lastModifiedHeader: "Mon, 01 Jan 2024 12:00:00 GMT",
            lastSyncError: "Previous error"
        )
        try harness.feedRepository.insert(feed)
        _ = try harness.insertArticle(
            feed: feed,
            externalID: "existing-article",
            url: "https://example.com/articles/existing",
            title: "Existing Article"
        )
        let saveProbe = FeedSaveFailureProbe(failingSaveCalls: [2])
        let feedRepository = SwiftDataFeedRepository(
            modelContext: harness.modelContainer.mainContext,
            persistenceSaveOperation: saveProbe.save
        )
        let service = makeService(
            client: client,
            harness: harness,
            feedRepository: feedRepository
        )

        let result = await service.refresh(feedID: feed.id)

        #expect(result.status == .failed)
        #expect(result.errorDescription?.contains("injected_feed_save_failure_call_2") == true)
        #expect(saveProbe.saveCallCount == 3)

        let finalSaveSnapshot = try #require(saveProbe.failureSnapshot(for: 2))
        #expect(finalSaveSnapshot.hasChanges)
        #expect(finalSaveSnapshot.lastETag == "\"staged-etag\"")
        #expect(finalSaveSnapshot.lastModifiedHeader == "Wed, 03 Jan 2024 12:00:00 GMT")
        #expect(finalSaveSnapshot.lastSyncError == nil)
        #expect(finalSaveSnapshot.insertedArticleTitles.isEmpty)

        let persistedFeed = try #require(try feedRepository.fetchFeed(id: feed.id))
        #expect(persistedFeed.lastFetchedAt != nil)
        #expect(persistedFeed.lastSuccessfulFetchAt == oldSuccessAt)
        #expect(persistedFeed.lastETag == "\"original-etag\"")
        #expect(persistedFeed.lastModifiedHeader == "Mon, 01 Jan 2024 12:00:00 GMT")
        #expect(persistedFeed.lastSyncError?.contains("injected_feed_save_failure_call_2") == true)
        #expect(try harness.articleRepository.fetchArticles(feedID: feed.id).map(\.title) == ["Existing Article"])
        #expect(harness.modelContainer.mainContext.hasChanges == false)
    }

    @Test
    func failureStateSaveFailureRollsBackBeforeDiagnosticsSave() async throws {
        let feedURL = "https://example.com/failure-state-save-failure.xml"
        let client = ScriptedHTTPClient(
            responsesByURL: [
                feedURL: .response(
                    statusCode: 200,
                    headers: ["Content-Type": "application/rss+xml; charset=utf-8"],
                    body: makeValidRSSFeedXML(
                        channelTitle: "Staged Feed",
                        channelLink: "https://example.com/staged/",
                        language: "en",
                        itemTitle: "Staged Article",
                        itemLink: "https://example.com/articles/staged",
                        itemGUID: "staged-article",
                        itemDescription: "Staged summary",
                        pubDate: "Tue, 02 Jan 2024 10:00:00 GMT"
                    )
                )
            ]
        )
        let logger = RecordingLogger()
        let harness = try TestHarness.make(httpClient: client, logger: logger)
        let feed = Feed(
            url: feedURL,
            title: "Original Feed",
            lastSyncError: "Previous error"
        )
        try harness.feedRepository.insert(feed)
        let saveProbe = FeedSaveFailureProbe(failingSaveCalls: [2, 3])
        let feedRepository = SwiftDataFeedRepository(
            modelContext: harness.modelContainer.mainContext,
            persistenceSaveOperation: saveProbe.save
        )
        let service = makeService(
            client: client,
            harness: harness,
            feedRepository: feedRepository,
            logger: logger
        )

        let result = await service.refresh(feedID: feed.id)

        #expect(result.status == .failed)
        #expect(result.errorDescription?.contains("injected_feed_save_failure_call_2") == true)
        #expect(saveProbe.saveCallCount == 3)
        let failureStateSnapshot = try #require(saveProbe.failureSnapshot(for: 3))
        #expect(failureStateSnapshot.hasChanges)
        #expect(failureStateSnapshot.lastSyncError?.contains("injected_feed_save_failure_call_2") == true)

        let persistedFeed = try #require(try feedRepository.fetchFeed(id: feed.id))
        #expect(persistedFeed.title == "Original Feed")
        #expect(persistedFeed.lastFetchedAt != nil)
        #expect(persistedFeed.lastSuccessfulFetchAt == nil)
        #expect(persistedFeed.lastSyncError == "Previous error")
        #expect(try harness.articleRepository.fetchArticles(feedID: feed.id).isEmpty)

        let log = try #require(try harness.feedFetchLogRepository.fetchLatestLog(feedID: feed.id))
        #expect(log.status == "failed")
        #expect(log.message?.contains("injected_feed_save_failure_call_2") == true)
        #expect(harness.modelContainer.mainContext.hasChanges == false)
        #expect(logger.contains("refresh_failure_state_persistence_failed", level: .error))
        #expect(logger.contains("feedID=\(feed.id.uuidString)", level: .error))
        #expect(logger.contains("injected_feed_save_failure_call_3", level: .error))
        #expect(logger.contains("failed refresh result preserved", level: .error))
    }

    private func makeService(
        client: ScriptedHTTPClient,
        harness: TestHarness,
        feedRepository: any FeedRepository,
        logger: Logging = TestLogger()
    ) -> FeedRefreshService {
        FeedRefreshService(
            logger: logger,
            feedFetcher: FeedFetcher(
                httpClient: client,
                retryPolicy: FeedRetryPolicy(maxAttempts: 1, baseDelayNanoseconds: 0)
            ),
            feedRepository: feedRepository,
            articleRepository: harness.articleRepository,
            feedFetchLogRepository: harness.feedFetchLogRepository
        )
    }
}

@MainActor
private final class FeedSaveFailureProbe {
    struct FailureSnapshot {
        let saveCall: Int
        let hasChanges: Bool
        let feedTitle: String?
        let lastETag: String?
        let lastModifiedHeader: String?
        let lastSyncError: String?
        let insertedArticleTitles: [String]
    }

    struct InjectedFailure: Error, CustomStringConvertible {
        let saveCall: Int

        var description: String {
            "injected_feed_save_failure_call_\(saveCall)"
        }
    }

    private let failingSaveCalls: Set<Int>
    private(set) var saveCallCount = 0
    private(set) var failureSnapshots: [FailureSnapshot] = []

    init(failingSaveCalls: Set<Int>) {
        self.failingSaveCalls = failingSaveCalls
    }

    func save(modelContext: ModelContext) throws {
        saveCallCount += 1
        guard failingSaveCalls.contains(saveCallCount) else {
            try modelContext.save()
            return
        }

        let feed = try modelContext.fetch(FetchDescriptor<Feed>()).first
        failureSnapshots.append(
            FailureSnapshot(
                saveCall: saveCallCount,
                hasChanges: modelContext.hasChanges,
                feedTitle: feed?.title,
                lastETag: feed?.lastETag,
                lastModifiedHeader: feed?.lastModifiedHeader,
                lastSyncError: feed?.lastSyncError,
                insertedArticleTitles: modelContext.insertedModelsArray
                    .compactMap { ($0 as? Article)?.title }
                    .sorted()
            )
        )
        throw InjectedFailure(saveCall: saveCallCount)
    }

    func failureSnapshot(for saveCall: Int) -> FailureSnapshot? {
        failureSnapshots.first { $0.saveCall == saveCall }
    }
}
