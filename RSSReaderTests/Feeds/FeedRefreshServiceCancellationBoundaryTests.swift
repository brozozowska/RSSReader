import Foundation
import SwiftData
import Testing
@testable import RSSReader

@Suite("Feeds / Refresh Service / Cancellation Boundaries")
@MainActor
struct FeedRefreshServiceCancellationBoundaryTests {
    @Test(arguments: FetchedCancellationStage.allCases)
    func fetchedRefreshCancellationRollsBackAndAllowsRetry(
        stage: FetchedCancellationStage
    ) async throws {
        let feedURL = "https://example.com/cancellation-boundary-\(stage.fixtureName).xml"
        let responseBody = makeValidRSSFeedXML(
            channelTitle: "Updated Feed",
            channelLink: "https://example.com/updated/",
            language: "en",
            itemTitle: "New Article",
            itemLink: "https://example.com/articles/new",
            itemGUID: "new-article",
            itemDescription: "New summary",
            pubDate: "Tue, 02 Jan 2024 10:00:00 GMT"
        )
        let responseStep = ScriptedHTTPClient.Step.response(
            statusCode: 200,
            headers: [
                "Content-Type": "application/rss+xml; charset=utf-8",
                "ETag": "\"updated-etag\""
            ],
            body: responseBody
        )
        let client = ScriptedHTTPClient(steps: [responseStep, responseStep])
        let discoveredIconURL = try #require(
            URL(string: "https://example.com/discovered-icon.png")
        )
        let iconDiscoveryService = RecordingFeedIconDiscoveryService(
            iconURL: discoveredIconURL
        )
        let harness = try TestHarness.make(
            httpClient: client,
            feedIconDiscoveryService: iconDiscoveryService
        )
        let feed = Feed(
            url: feedURL,
            siteURL: "https://example.com/original/",
            title: "Original Feed",
            lastETag: "\"original-etag\"",
            lastSyncError: "Previous error"
        )
        try harness.feedRepository.insert(feed)
        _ = try harness.insertArticle(
            feed: feed,
            externalID: "obsolete-article",
            guid: "obsolete-article",
            url: "https://example.com/articles/obsolete",
            title: "Obsolete Article"
        )

        let xmlProbe = OneShotXMLCancellationProbe(
            shouldInject: stage == .duringXMLParse
        )
        let entryProcessingProbe = OneShotEntryProcessingCancellationProbe(
            target: stage.entryProcessingStage
        )
        let payloadMaterializationProbe = OneShotPayloadMaterializationCancellationProbe(
            shouldInject: stage == .duringPayloadMaterialization
        )
        let parsingWorker = FeedParsingWorker(
            pipeline: { response in
                try FeedParserService.parsePipelineResult(
                    response,
                    xmlCancellationProbe: xmlProbe.shouldCancel,
                    entryProgressProbe: entryProcessingProbe.record
                )
            },
            payloadPreparation: { entries, fetchedAt in
                try ArticleUpsertPayload.makeAllPrepared(
                    entries: entries,
                    fetchedAt: fetchedAt,
                    materializationProbe: payloadMaterializationProbe.record
                )
            }
        )
        let articleCheckpoint = OneShotArticleCancellationCheckpoint(
            target: stage == .betweenReconciliationAndUpsert ? .beforeUpsert : nil
        )
        let articleRepository = SwiftDataArticleRepository(
            modelContext: harness.modelContainer.mainContext,
            cancellationCheckpoint: articleCheckpoint.check
        )
        let refreshCheckpoint = OneShotRefreshCancellationCheckpoint(
            target: stage.refreshCheckpoint
        )
        let service = FeedRefreshService(
            logger: TestLogger(),
            feedFetcher: FeedFetcher(
                httpClient: client,
                retryPolicy: FeedRetryPolicy(maxAttempts: 1, baseDelayNanoseconds: 0)
            ),
            feedParsingWorker: parsingWorker,
            feedRepository: harness.feedRepository,
            articleRepository: articleRepository,
            feedIconDiscoveryService: iconDiscoveryService,
            feedFetchLogRepository: harness.feedFetchLogRepository,
            cancellationCheckpoint: refreshCheckpoint.check
        )

        let cancelledResult = await service.refresh(feedID: feed.id)

        #expect(cancelledResult.status == .cancelled)
        #expect(service.inFlightRefreshTasks[feed.id] == nil)
        #expect(xmlProbe.didInject == (stage == .duringXMLParse))
        #expect(
            entryProcessingProbe.didInject
                == (stage == .duringNormalization)
        )
        #expect(
            payloadMaterializationProbe.didInject
                == (stage == .duringPayloadMaterialization)
        )
        #expect(
            articleCheckpoint.didInject
                == (stage == .betweenReconciliationAndUpsert)
        )
        #expect(refreshCheckpoint.didInject == (stage.refreshCheckpoint != nil))

        let rolledBackFeed = try #require(try harness.feedRepository.fetchFeed(id: feed.id))
        #expect(rolledBackFeed.title == "Original Feed")
        #expect(rolledBackFeed.siteURL == "https://example.com/original/")
        #expect(rolledBackFeed.iconURL == nil)
        #expect(rolledBackFeed.lastETag == "\"original-etag\"")
        #expect(rolledBackFeed.lastSuccessfulFetchAt == nil)
        #expect(rolledBackFeed.lastSyncError == "Previous error")
        #expect(rolledBackFeed.lastFetchedAt != nil)

        let rolledBackArticles = try articleRepository.fetchArticles(feedID: feed.id)
        let rolledBackObsoleteArticle = try #require(rolledBackArticles.first)
        #expect(rolledBackArticles.count == 1)
        #expect(rolledBackObsoleteArticle.externalID == "obsolete-article")
        #expect(rolledBackObsoleteArticle.archivedAt == nil)
        #expect(rolledBackObsoleteArticle.feedTitle == "Original Feed")

        let retryResult = await service.refresh(feedID: feed.id)

        #expect(retryResult.status == .fetched)
        #expect(service.inFlightRefreshTasks[feed.id] == nil)
        #expect(await client.recordedRequests().count == 2)
        #expect(
            iconDiscoveryService.calls.count
                == (stage.cancelsBeforeIconDiscovery ? 1 : 2)
        )

        let retriedFeed = try #require(try harness.feedRepository.fetchFeed(id: feed.id))
        #expect(retriedFeed.title == "Updated Feed")
        #expect(retriedFeed.siteURL == "https://example.com/updated/")
        #expect(retriedFeed.iconURL == discoveredIconURL.absoluteString)
        #expect(retriedFeed.lastETag == "\"updated-etag\"")
        #expect(retriedFeed.lastSuccessfulFetchAt != nil)
        #expect(retriedFeed.lastSyncError == nil)

        let retriedArticles = try articleRepository.fetchArticles(feedID: feed.id)
        let retriedObsoleteArticle = try #require(
            retriedArticles.first { $0.externalID == "obsolete-article" }
        )
        let insertedArticle = try #require(
            retriedArticles.first { $0.guid == "new-article" }
        )
        #expect(retriedArticles.count == 2)
        #expect(retriedObsoleteArticle.archivedAt != nil)
        #expect(insertedArticle.title == "New Article")
    }

    @Test
    func notModifiedCancellationBeforeSaveRollsBackAndAllowsRetry() async throws {
        let feedURL = "https://example.com/not-modified-cancellation-boundary.xml"
        let responseStep = ScriptedHTTPClient.Step.response(
            statusCode: 304,
            headers: [
                "ETag": "\"updated-etag\"",
                "Last-Modified": "Wed, 03 Jan 2024 12:00:00 GMT"
            ],
            body: ""
        )
        let client = ScriptedHTTPClient(steps: [responseStep, responseStep])
        let discoveredIconURL = try #require(
            URL(string: "https://example.com/discovered-icon.png")
        )
        let iconDiscoveryService = RecordingFeedIconDiscoveryService(
            iconURL: discoveredIconURL
        )
        let harness = try TestHarness.make(
            httpClient: client,
            feedIconDiscoveryService: iconDiscoveryService
        )
        let oldSuccessAt = Date(timeIntervalSince1970: 1_700_000_000)
        let feed = Feed(
            url: feedURL,
            siteURL: "https://example.com/",
            title: "Stable Feed",
            iconURL: "https://example.com/original-icon.png",
            lastSuccessfulFetchAt: oldSuccessAt,
            lastETag: "\"original-etag\"",
            lastModifiedHeader: "Mon, 01 Jan 2024 12:00:00 GMT",
            lastSyncError: "Previous error"
        )
        try harness.feedRepository.insert(feed)
        let refreshCheckpoint = OneShotRefreshCancellationCheckpoint(
            target: .beforeNotModifiedSave
        )
        let service = FeedRefreshService(
            logger: TestLogger(),
            feedFetcher: FeedFetcher(
                httpClient: client,
                retryPolicy: FeedRetryPolicy(maxAttempts: 1, baseDelayNanoseconds: 0)
            ),
            feedRepository: harness.feedRepository,
            articleRepository: harness.articleRepository,
            feedIconDiscoveryService: iconDiscoveryService,
            feedFetchLogRepository: harness.feedFetchLogRepository,
            cancellationCheckpoint: refreshCheckpoint.check
        )

        let cancelledResult = await service.refresh(feedID: feed.id)

        #expect(cancelledResult.status == .cancelled)
        #expect(refreshCheckpoint.didInject)
        #expect(service.inFlightRefreshTasks[feed.id] == nil)

        let rolledBackFeed = try #require(try harness.feedRepository.fetchFeed(id: feed.id))
        #expect(rolledBackFeed.iconURL == "https://example.com/original-icon.png")
        #expect(rolledBackFeed.lastSuccessfulFetchAt == oldSuccessAt)
        #expect(rolledBackFeed.lastETag == "\"original-etag\"")
        #expect(rolledBackFeed.lastModifiedHeader == "Mon, 01 Jan 2024 12:00:00 GMT")
        #expect(rolledBackFeed.lastSyncError == "Previous error")
        #expect(rolledBackFeed.lastFetchedAt != nil)

        let retryResult = await service.refresh(feedID: feed.id)

        #expect(retryResult.status == .notModified)
        #expect(service.inFlightRefreshTasks[feed.id] == nil)
        #expect(await client.recordedRequests().count == 2)
        #expect(iconDiscoveryService.calls.count == 2)

        let retriedFeed = try #require(try harness.feedRepository.fetchFeed(id: feed.id))
        #expect(retriedFeed.iconURL == discoveredIconURL.absoluteString)
        #expect(retriedFeed.lastSuccessfulFetchAt == oldSuccessAt)
        #expect(retriedFeed.lastETag == "\"updated-etag\"")
        #expect(retriedFeed.lastModifiedHeader == "Wed, 03 Jan 2024 12:00:00 GMT")
        #expect(retriedFeed.lastSyncError == nil)
    }
}

enum FetchedCancellationStage: CaseIterable, Sendable {
    case duringXMLParse
    case duringNormalization
    case duringPayloadMaterialization
    case afterIconDiscovery
    case betweenReconciliationAndUpsert
    case beforeFetchedSave

    var fixtureName: String {
        switch self {
        case .duringXMLParse:
            "xml-parse"
        case .duringNormalization:
            "normalization"
        case .duringPayloadMaterialization:
            "payload-materialization"
        case .afterIconDiscovery:
            "icon-discovery"
        case .betweenReconciliationAndUpsert:
            "reconciliation-upsert"
        case .beforeFetchedSave:
            "fetched-save"
        }
    }

    var refreshCheckpoint: FeedRefreshCancellationCheckpoint? {
        switch self {
        case .afterIconDiscovery:
            .afterIconDiscovery
        case .beforeFetchedSave:
            .beforeFetchedSave
        case .duringXMLParse,
             .duringNormalization,
             .duringPayloadMaterialization,
             .betweenReconciliationAndUpsert:
            nil
        }
    }

    var entryProcessingStage: FeedParsingEntryStage? {
        self == .duringNormalization ? .normalization : nil
    }

    var cancelsBeforeIconDiscovery: Bool {
        switch self {
        case .duringXMLParse, .duringNormalization, .duringPayloadMaterialization:
            true
        case .afterIconDiscovery, .betweenReconciliationAndUpsert, .beforeFetchedSave:
            false
        }
    }
}

private final class OneShotXMLCancellationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let shouldInjectCancellation: Bool
    private var callbackCount = 0
    private var hasInjected = false

    init(shouldInject: Bool) {
        self.shouldInjectCancellation = shouldInject
    }

    var didInject: Bool {
        lock.withLock { hasInjected }
    }

    func shouldCancel() -> Bool {
        lock.withLock {
            guard shouldInjectCancellation, hasInjected == false else { return false }
            callbackCount += 1
            guard callbackCount >= 8 else { return false }
            hasInjected = true
            return true
        }
    }
}

private final class OneShotEntryProcessingCancellationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let target: FeedParsingEntryStage?
    private var hasInjected = false

    init(target: FeedParsingEntryStage?) {
        self.target = target
    }

    var didInject: Bool {
        lock.withLock { hasInjected }
    }

    func record(_ stage: FeedParsingEntryStage, _ processedEntryCount: Int) {
        let shouldCancel = lock.withLock {
            guard stage == target, processedEntryCount > 0, hasInjected == false else {
                return false
            }
            hasInjected = true
            return true
        }
        guard shouldCancel else { return }
        withUnsafeCurrentTask { task in
            task?.cancel()
        }
    }
}

private final class OneShotPayloadMaterializationCancellationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let shouldInjectCancellation: Bool
    private var hasInjected = false

    init(shouldInject: Bool) {
        self.shouldInjectCancellation = shouldInject
    }

    var didInject: Bool {
        lock.withLock { hasInjected }
    }

    func record(_ materializedPayloadCount: Int, _: ArticleUpsertPayload) {
        let shouldCancel = lock.withLock {
            guard shouldInjectCancellation,
                  materializedPayloadCount > 0,
                  hasInjected == false else {
                return false
            }
            hasInjected = true
            return true
        }
        guard shouldCancel else { return }
        withUnsafeCurrentTask { task in
            task?.cancel()
        }
    }
}

@MainActor
private final class OneShotRefreshCancellationCheckpoint {
    private let target: FeedRefreshCancellationCheckpoint?
    private(set) var didInject = false

    init(target: FeedRefreshCancellationCheckpoint?) {
        self.target = target
    }

    func check(_ checkpoint: FeedRefreshCancellationCheckpoint) throws {
        try Task.checkCancellation()
        guard checkpoint == target, didInject == false else { return }
        didInject = true
        throw CancellationError()
    }
}

@MainActor
private final class OneShotArticleCancellationCheckpoint {
    private let target: ArticleFeedSnapshotCancellationCheckpoint?
    private(set) var didInject = false

    init(target: ArticleFeedSnapshotCancellationCheckpoint?) {
        self.target = target
    }

    func check(_ checkpoint: ArticleFeedSnapshotCancellationCheckpoint) throws {
        try Task.checkCancellation()
        guard checkpoint == target, didInject == false else { return }
        didInject = true
        throw CancellationError()
    }
}
