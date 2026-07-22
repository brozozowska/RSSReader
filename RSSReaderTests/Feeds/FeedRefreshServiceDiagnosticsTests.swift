import Foundation
import Testing
@testable import RSSReader

@Suite("Feeds / Refresh Service / Diagnostics")
@MainActor
struct FeedRefreshServiceDiagnosticsTests {
    @Test
    func fetchedResultSurvivesInjectedFetchLogSaveFailureAfterFeedAndArticleCommit() async throws {
        let feedURL = "https://example.com/log-save-failure.xml"
        let logger = RecordingLogger()
        let client = ScriptedHTTPClient(
            responsesByURL: [
                feedURL: .response(
                    statusCode: 200,
                    headers: ["Content-Type": "application/rss+xml; charset=utf-8"],
                    body: makeValidRSSFeedXML(
                        channelTitle: "Committed Feed",
                        channelLink: "https://example.com/",
                        language: "en",
                        itemTitle: "Committed Article",
                        itemLink: "https://example.com/articles/committed",
                        itemGUID: "committed-article",
                        itemDescription: "Committed summary",
                        pubDate: "Tue, 02 Jan 2024 10:00:00 GMT"
                    )
                )
            ]
        )
        let harness = try TestHarness.make(httpClient: client, logger: logger)
        let feed = try #require(try harness.insertFeeds(urls: [feedURL]).first)
        let failingLogRepository = FailingInsertFeedFetchLogRepository(
            backing: harness.feedFetchLogRepository
        )
        let service = makeService(
            client: client,
            harness: harness,
            logger: logger,
            feedFetchLogRepository: failingLogRepository
        )

        let result = await service.refresh(feedID: feed.id)

        #expect(result.status == .fetched)
        #expect(result.errorDescription == nil)
        let refreshedFeed = try #require(try harness.fetchFeed(id: feed.id))
        #expect(refreshedFeed.title == "Committed Feed")
        #expect(refreshedFeed.lastSuccessfulFetchAt != nil)
        #expect(refreshedFeed.lastSyncError == nil)
        #expect(try harness.articleRepository.fetchArticles(feedID: feed.id).map(\.title) == ["Committed Article"])
        #expect(try harness.feedFetchLogRepository.fetchLogs(feedID: feed.id, limit: nil).isEmpty)
        #expect(failingLogRepository.rollbackCallCount == 1)
        #expect(logger.contains("refresh_diagnostics_persistence_failed", level: .error))
        #expect(logger.contains("status=fetched", level: .error))
        #expect(logger.contains("refresh result preserved", level: .error))
    }

    @Test
    func notModifiedResultSurvivesInjectedFetchLogSaveFailure() async throws {
        let feedURL = "https://example.com/not-modified-log-save-failure.xml"
        let logger = RecordingLogger()
        let client = ScriptedHTTPClient(
            responsesByURL: [
                feedURL: .response(
                    statusCode: 304,
                    headers: ["ETag": "\"etag-preserved\""],
                    body: ""
                )
            ]
        )
        let harness = try TestHarness.make(httpClient: client, logger: logger)
        let feed = Feed(url: feedURL, title: "Not Modified", lastSyncError: "Previous error")
        try harness.feedRepository.insert(feed)
        let failingLogRepository = FailingInsertFeedFetchLogRepository(
            backing: harness.feedFetchLogRepository
        )
        let service = makeService(
            client: client,
            harness: harness,
            logger: logger,
            feedFetchLogRepository: failingLogRepository
        )

        let result = await service.refresh(feedID: feed.id)

        #expect(result.status == .notModified)
        #expect(result.errorDescription == nil)
        let refreshedFeed = try #require(try harness.fetchFeed(id: feed.id))
        #expect(refreshedFeed.lastETag == "\"etag-preserved\"")
        #expect(refreshedFeed.lastSyncError == nil)
        #expect(try harness.feedFetchLogRepository.fetchLogs(feedID: feed.id, limit: nil).isEmpty)
        #expect(failingLogRepository.rollbackCallCount == 1)
        #expect(logger.contains("refresh_diagnostics_persistence_failed", level: .error))
        #expect(logger.contains("status=not_modified", level: .error))
    }

    @Test
    func diagnosticsLoggingCapsDetailsAndReportsTruncationWithoutChangingCounts() throws {
        let logger = RecordingLogger()
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(),
            logger: logger
        )
        let policy = FeedRefreshDiagnosticsPolicy.default
        let anomalyCount = policy.maximumLoggedParserAnomalyDetails + 3
        let rejectedCount = policy.maximumLoggedRejectedEntryDetails + 4
        let diagnostics = FeedParsePipelineDiagnostics(
            parserAnomalies: (0..<anomalyCount).map { index in
                FeedParserAnomaly(
                    kind: .entryMissingTitle,
                    entryIndex: index,
                    message: "Missing title \(index)"
                )
            },
            rejectedEntries: (0..<rejectedCount).map { _ in
                RejectedFeedEntryDiagnostic(
                    entry: ParsedFeedEntryDTO(),
                    reasons: [.missingExternalID]
                )
            }
        )
        let feedID = UUID()

        harness.service.logDiagnosticsIfNeeded(diagnostics, feedID: feedID)

        let anomalyDetails = logger.entries.filter { $0.message.contains(" anomaly [") }
        let rejectedDetails = logger.entries.filter { $0.message.contains("rejected entry reasons:") }
        #expect(anomalyDetails.count == policy.maximumLoggedParserAnomalyDetails)
        #expect(rejectedDetails.count == policy.maximumLoggedRejectedEntryDetails)
        #expect(logger.contains("parser anomalies: \(anomalyCount)", level: .info))
        #expect(logger.contains("rejected entries: \(rejectedCount)", level: .info))
        #expect(
            logger.contains(
                "parser anomaly details truncated: logged \(policy.maximumLoggedParserAnomalyDetails) of \(anomalyCount)",
                level: .info
            )
        )
        #expect(
            logger.contains(
                "rejected entry details truncated: logged \(policy.maximumLoggedRejectedEntryDetails) of \(rejectedCount)",
                level: .info
            )
        )
    }

    @Test
    func refreshFetchedPayloadPersistsRejectedEntryDiagnosticsAndFetchLogMessage() async throws {
        let feedURL = "https://example.com/diagnostics.xml"
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(
                responsesByURL: [
                    feedURL: .response(
                        statusCode: 200,
                        headers: [
                            "Content-Type": "application/rss+xml; charset=utf-8"
                        ],
                        body: makeRSSFeedWithValidAndRejectedEntries(
                            channelTitle: "Diagnostics Feed",
                            channelLink: "https://example.com/",
                            validItemTitle: "Valid Diagnostics Article",
                            validItemLink: "https://example.com/articles/valid",
                            validItemGUID: "valid-diagnostics-article"
                        )
                    )
                ]
            )
        )
        let feed = try #require(try harness.insertFeeds(urls: [feedURL]).first)

        let result = await harness.service.refresh(feedID: feed.id)

        #expect(result.status == .fetched)
        #expect(result.processedEntryCount == 2)
        #expect(result.upsertedEntryCount == 1)
        #expect(result.rejectedEntryCount == 1)
        #expect(result.diagnosticsSummary.parserAnomalyCount == 4)
        #expect(result.diagnosticsSummary.rejectedEntryCount == 1)
        #expect(result.diagnosticsSummary.hasSoftFailures)

        let articles = try harness.articleRepository.fetchArticles(feedID: feed.id)
        #expect(articles.map(\.title) == ["Valid Diagnostics Article"])

        let latestLog = try #require(try harness.feedFetchLogRepository.fetchLatestLog(feedID: feed.id))
        #expect(latestLog.status == "fetched")
        #expect(latestLog.httpCode == 200)
        #expect(latestLog.message?.contains("diagnostics(parser_anomalies=4, rejected_entries=1)") == true)
    }

    @Test
    func refreshParseFailurePersistsFailureStateAndFetchLogWithoutArticles() async throws {
        let feedURL = "https://example.com/malformed.xml"
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(
                responsesByURL: [
                    feedURL: .response(
                        statusCode: 200,
                        headers: [
                            "Content-Type": "application/rss+xml; charset=utf-8"
                        ],
                        body: """
                        <?xml version="1.0" encoding="UTF-8"?>
                        <rss version="2.0">
                          <channel>
                            <title>Malformed Feed</title>
                        """
                    )
                ]
            )
        )
        let feed = try #require(try harness.insertFeeds(urls: [feedURL]).first)

        let result = await harness.service.refresh(feedID: feed.id)

        #expect(result.status == .failed)
        #expect(result.processedEntryCount == 0)
        #expect(result.upsertedEntryCount == 0)
        #expect(result.rejectedEntryCount == 0)
        #expect(result.diagnosticsSummary.parserAnomalyCount == 0)
        #expect(result.diagnosticsSummary.rejectedEntryCount == 0)
        #expect(result.errorDescription?.contains("malformedXML") == true)

        let refreshedFeed = try #require(try harness.fetchFeed(id: feed.id))
        #expect(refreshedFeed.lastFetchedAt != nil)
        #expect(refreshedFeed.lastSuccessfulFetchAt == nil)
        #expect(refreshedFeed.lastSyncError?.contains("malformedXML") == true)
        #expect(try harness.articleRepository.fetchArticles(feedID: feed.id).isEmpty)

        let latestLog = try #require(try harness.feedFetchLogRepository.fetchLatestLog(feedID: feed.id))
        #expect(latestLog.status == "failed")
        #expect(latestLog.httpCode == nil)
        #expect(latestLog.message?.contains("diagnostics(parser_anomalies=0, rejected_entries=0)") == true)
        #expect(latestLog.message?.contains("malformedXML") == true)
    }

    @Test
    func refreshNotModifiedPersistsDiagnosticsLogMessageWithoutPayloadSideEffects() async throws {
        let feedURL = "https://example.com/not-modified-diagnostics.xml"
        let oldSuccessAt = Date(timeIntervalSince1970: 1_700_000_000)
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(
                responsesByURL: [
                    feedURL: .response(
                        statusCode: 304,
                        headers: [
                            "ETag": "\"etag-not-modified\"",
                            "Last-Modified": "Wed, 03 Jan 2024 12:00:00 GMT"
                        ],
                        body: ""
                    )
                ]
            )
        )
        let feed = Feed(
            url: feedURL,
            title: "Not Modified Diagnostics",
            lastSuccessfulFetchAt: oldSuccessAt,
            lastETag: "\"etag-old\"",
            lastModifiedHeader: "Tue, 02 Jan 2024 12:00:00 GMT",
            lastSyncError: "Previous error"
        )
        try harness.feedRepository.insert(feed)

        let result = await harness.service.refresh(feedID: feed.id)

        #expect(result.status == .notModified)
        #expect(result.diagnosticsSummary.parserAnomalyCount == 0)
        #expect(result.diagnosticsSummary.rejectedEntryCount == 0)
        #expect(result.errorDescription == nil)
        #expect(try harness.articleRepository.fetchArticles(feedID: feed.id).isEmpty)

        let refreshedFeed = try #require(try harness.fetchFeed(id: feed.id))
        #expect(refreshedFeed.lastSuccessfulFetchAt == oldSuccessAt)
        #expect(refreshedFeed.lastETag == "\"etag-not-modified\"")
        #expect(refreshedFeed.lastModifiedHeader == "Wed, 03 Jan 2024 12:00:00 GMT")
        #expect(refreshedFeed.lastSyncError == nil)

        let latestLog = try #require(try harness.feedFetchLogRepository.fetchLatestLog(feedID: feed.id))
        #expect(latestLog.status == "not_modified")
        #expect(latestLog.httpCode == 304)
        #expect(latestLog.message?.contains("Feed not modified") == true)
        #expect(latestLog.message?.contains("diagnostics(parser_anomalies=0, rejected_entries=0)") == true)
    }

    @Test
    func batchRefreshAggregatesDiagnosticsAndUsesOnlyScriptedRequests() async throws {
        let fetchedURL = "https://example.com/batch-diagnostics-fetched.xml"
        let notModifiedURL = "https://example.com/batch-diagnostics-not-modified.xml"
        let failedURL = "https://example.com/batch-diagnostics-failed.xml"
        let client = ScriptedHTTPClient(
            responsesByURL: [
                fetchedURL: .response(
                    statusCode: 200,
                    headers: [
                        "Content-Type": "application/rss+xml; charset=utf-8"
                    ],
                    body: makeRSSFeedWithValidAndRejectedEntries(
                        channelTitle: "Batch Diagnostics Fetched",
                        channelLink: "https://example.com/batch/",
                        validItemTitle: "Batch Valid Article",
                        validItemLink: "https://example.com/batch/articles/valid",
                        validItemGUID: "batch-valid-article"
                    )
                ),
                notModifiedURL: .response(
                    statusCode: 304,
                    headers: [
                        "ETag": "\"etag-batch-not-modified\""
                    ],
                    body: ""
                ),
                failedURL: .response(
                    statusCode: 200,
                    headers: [
                        "Content-Type": "application/rss+xml; charset=utf-8"
                    ],
                    body: "<rss><channel><title>Broken"
                )
            ]
        )
        let harness = try TestHarness.make(httpClient: client)
        let feeds = try harness.insertFeeds(urls: [fetchedURL, notModifiedURL, failedURL])

        let result = await harness.service.refreshFeeds(feeds.map(\.id))

        #expect(result.results.map(\.status) == [.fetched, .notModified, .failed])
        #expect(result.summary.totalFeedCount == 3)
        #expect(result.summary.fetchedCount == 1)
        #expect(result.summary.notModifiedCount == 1)
        #expect(result.summary.failedCount == 1)
        #expect(result.summary.cancelledCount == 0)
        #expect(result.summary.totalProcessedEntryCount == 2)
        #expect(result.summary.totalUpsertedEntryCount == 1)
        #expect(result.summary.totalRejectedEntryCount == 1)
        #expect(result.errors.count == 1)
        #expect(result.errors.first?.feedID == feeds[2].id)
        #expect(result.errors.first?.message.contains("malformedXML") == true)

        let fetchedLogs = try harness.feedFetchLogRepository.fetchLogs(feedID: feeds[0].id, limit: nil)
        let notModifiedLogs = try harness.feedFetchLogRepository.fetchLogs(feedID: feeds[1].id, limit: nil)
        let failedLogs = try harness.feedFetchLogRepository.fetchLogs(feedID: feeds[2].id, limit: nil)
        #expect(fetchedLogs.first?.message?.contains("diagnostics(parser_anomalies=4, rejected_entries=1)") == true)
        #expect(notModifiedLogs.first?.status == "not_modified")
        #expect(failedLogs.first?.message?.contains("malformedXML") == true)

        let requestedURLs = Set(await client.recordedRequests().map(\.url.absoluteString))
        #expect(requestedURLs == Set([fetchedURL, notModifiedURL, failedURL]))
    }

    private func makeRSSFeedWithValidAndRejectedEntries(
        channelTitle: String,
        channelLink: String,
        validItemTitle: String,
        validItemLink: String,
        validItemGUID: String
    ) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
          <channel>
            <title>\(channelTitle)</title>
            <link>\(channelLink)</link>
            <description>Diagnostics feed</description>
            <language>en</language>
            <item>
              <title>\(validItemTitle)</title>
              <link>\(validItemLink)</link>
              <guid isPermaLink="false">\(validItemGUID)</guid>
              <description>Readable summary</description>
              <pubDate>Tue, 02 Jan 2024 10:00:00 GMT</pubDate>
            </item>
            <item>
            </item>
          </channel>
        </rss>
        """
    }

    private func makeService(
        client: ScriptedHTTPClient,
        harness: TestHarness,
        logger: Logging,
        feedFetchLogRepository: any FeedFetchLogRepository
    ) -> FeedRefreshService {
        FeedRefreshService(
            logger: logger,
            feedFetcher: FeedFetcher(
                httpClient: client,
                retryPolicy: FeedRetryPolicy(maxAttempts: 1, baseDelayNanoseconds: 0)
            ),
            feedRepository: harness.feedRepository,
            articleRepository: harness.articleRepository,
            feedFetchLogRepository: feedFetchLogRepository
        )
    }
}

@MainActor
private final class FailingInsertFeedFetchLogRepository: FeedFetchLogRepository {
    private enum InjectedFailure: Error {
        case logSave
    }

    private let backing: any FeedFetchLogRepository
    private(set) var rollbackCallCount = 0

    init(backing: any FeedFetchLogRepository) {
        self.backing = backing
    }

    func fetchLogs(feedID: UUID, limit: Int?) throws -> [FeedFetchLog] {
        try backing.fetchLogs(feedID: feedID, limit: limit)
    }

    func fetchLatestLog(feedID: UUID) throws -> FeedFetchLog? {
        try backing.fetchLatestLog(feedID: feedID)
    }

    func insert(_ entry: FeedFetchLogEntry) throws -> FeedFetchLog {
        throw InjectedFailure.logSave
    }

    func insert(_ entries: [FeedFetchLogEntry]) throws -> [FeedFetchLog] {
        try backing.insert(entries)
    }

    func insert(_ log: FeedFetchLog) throws -> FeedFetchLog {
        try backing.insert(log)
    }

    func insert(_ logs: [FeedFetchLog]) throws -> [FeedFetchLog] {
        try backing.insert(logs)
    }

    func deleteLogs(
        olderThan cutoffDate: Date,
        batchSize: Int
    ) throws -> RepositoryBatchDeleteResult {
        try backing.deleteLogs(olderThan: cutoffDate, batchSize: batchSize)
    }

    func deleteLogsExceedingPerFeedCount(
        _ maximumCountPerFeed: Int,
        batchSize: Int
    ) throws -> RepositoryBatchDeleteResult {
        try backing.deleteLogsExceedingPerFeedCount(maximumCountPerFeed, batchSize: batchSize)
    }

    func save() throws {
        try backing.save()
    }

    func rollback() {
        rollbackCallCount += 1
        backing.rollback()
    }
}
