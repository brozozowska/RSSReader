import Foundation
import Testing
import UIKit
@testable import RSSReader

@Suite("Article Screen / Adjacent Image Prefetch")
@MainActor
struct ReaderAdjacentArticleImagePrefetcherTests {
    @Test
    func prefetchSelectsOnlyFirstRenderedImageFromEachCandidateArticle() async throws {
        let currentID = UUID()
        let previousID = UUID()
        let nextID = UUID()
        let firstPreviousURL = try #require(URL(string: "https://example.com/previous-first.png"))
        let nextLeadURL = try #require(URL(string: "https://example.com/next-lead.png"))
        let articleQueryService = PrefetchArticleQueryService(
            articlesByID: [
                previousID: makeReaderArticleDTO(
                    id: previousID,
                    contentHTML: """
                    <p>Previous</p>
                    <img src="\(firstPreviousURL.absoluteString)">
                    <img src="https://example.com/previous-second.png">
                    """,
                    imageURL: "https://example.com/previous-lead.png"
                ),
                nextID: makeReaderArticleDTO(
                    id: nextID,
                    summary: "Next summary",
                    imageURL: nextLeadURL.absoluteString
                )
            ]
        )
        let context = makeContext(
            currentArticleID: currentID,
            previousArticleID: previousID,
            nextArticleID: nextID
        )

        let plan = try ReaderAdjacentArticleImagePrefetcher.plan(
            context: context,
            articleQueryService: articleQueryService
        )

        #expect(articleQueryService.requestedArticleIDs == [currentID, previousID, nextID])
        #expect(plan.adjacentImageURLs == [firstPreviousURL, nextLeadURL])
        #expect(plan.reservationURLs == [firstPreviousURL, nextLeadURL])
    }

    @Test
    func contextBoundsCandidatesAndDeduplicatesCurrentAndRepeatedAdjacentIDs() {
        let currentID = UUID()
        let repeatedAdjacentID = UUID()

        let excludesCurrent = makeContext(
            currentArticleID: currentID,
            previousArticleID: currentID,
            nextArticleID: repeatedAdjacentID
        )
        let deduplicatesAdjacent = makeContext(
            currentArticleID: currentID,
            previousArticleID: repeatedAdjacentID,
            nextArticleID: repeatedAdjacentID
        )

        #expect(excludesCurrent.articleIDs == [currentID, repeatedAdjacentID])
        #expect(deduplicatesAdjacent.articleIDs == [currentID, repeatedAdjacentID])
    }

    @Test
    func prefetchScansPastImageLessArticlesAndKeepsTwoImagesPerDirection() async throws {
        let previousWithoutImageID = UUID()
        let firstPreviousImageID = UUID()
        let secondPreviousImageID = UUID()
        let ignoredPreviousImageID = UUID()
        let nextWithoutImageID = UUID()
        let firstNextImageID = UUID()
        let secondNextImageID = UUID()
        let previousURLs = try [
            #require(URL(string: "https://example.com/previous-1.png")),
            #require(URL(string: "https://example.com/previous-2.png")),
            #require(URL(string: "https://example.com/previous-ignored.png"))
        ]
        let nextURLs = try [
            #require(URL(string: "https://example.com/next-1.png")),
            #require(URL(string: "https://example.com/next-2.png"))
        ]
        let articleQueryService = PrefetchArticleQueryService(
            articlesByID: [
                previousWithoutImageID: makeReaderArticleDTO(id: previousWithoutImageID),
                firstPreviousImageID: makeReaderArticleDTO(
                    id: firstPreviousImageID,
                    imageURL: previousURLs[0].absoluteString
                ),
                secondPreviousImageID: makeReaderArticleDTO(
                    id: secondPreviousImageID,
                    imageURL: previousURLs[1].absoluteString
                ),
                ignoredPreviousImageID: makeReaderArticleDTO(
                    id: ignoredPreviousImageID,
                    imageURL: previousURLs[2].absoluteString
                ),
                nextWithoutImageID: makeReaderArticleDTO(id: nextWithoutImageID),
                firstNextImageID: makeReaderArticleDTO(
                    id: firstNextImageID,
                    imageURL: nextURLs[0].absoluteString
                ),
                secondNextImageID: makeReaderArticleDTO(
                    id: secondNextImageID,
                    imageURL: nextURLs[1].absoluteString
                )
            ]
        )
        let previousCandidates = [
            previousWithoutImageID,
            firstPreviousImageID,
            secondPreviousImageID,
            ignoredPreviousImageID
        ]
        let nextCandidates = [nextWithoutImageID, firstNextImageID, secondNextImageID]

        let plan = try ReaderAdjacentArticleImagePrefetcher.plan(
            context: makeContext(
                previousCandidateArticleIDs: previousCandidates,
                nextCandidateArticleIDs: nextCandidates
            ),
            articleQueryService: articleQueryService
        )

        #expect(Array(articleQueryService.requestedArticleIDs.dropFirst()) == previousCandidates + nextCandidates)
        #expect(plan.adjacentImageURLs == [
            previousURLs[0],
            nextURLs[0],
            previousURLs[1],
            nextURLs[1]
        ])
    }

    @Test
    func sharedURLIsPrefetchedOnlyOnceAcrossBothAdjacentArticles() async throws {
        let previousID = UUID()
        let nextID = UUID()
        let sharedURL = try #require(URL(string: "https://example.com/shared.png"))
        let articleQueryService = PrefetchArticleQueryService(
            articlesByID: [
                previousID: makeReaderArticleDTO(id: previousID, imageURL: sharedURL.absoluteString),
                nextID: makeReaderArticleDTO(id: nextID, imageURL: sharedURL.absoluteString)
            ]
        )
        let plan = try ReaderAdjacentArticleImagePrefetcher.plan(
            context: makeContext(previousArticleID: previousID, nextArticleID: nextID),
            articleQueryService: articleQueryService
        )

        #expect(plan.adjacentImageURLs == [sharedURL])
    }

    @Test
    func adjacentArticlesWithoutRenderedImagesClearPreviousReservationWindow() async throws {
        let nextID = UUID()
        let articleQueryService = PrefetchArticleQueryService(
            articlesByID: [
                nextID: makeReaderArticleDTO(
                    id: nextID,
                    summary: nil,
                    contentHTML: nil,
                    contentText: nil,
                    imageURL: nil
                )
            ]
        )
        let plan = try ReaderAdjacentArticleImagePrefetcher.plan(
            context: makeContext(nextArticleID: nextID),
            articleQueryService: articleQueryService
        )

        #expect(plan.reservationURLs.isEmpty)
        #expect(plan.adjacentImageURLs.isEmpty)
    }

    @Test
    func planKeepsCurrentImageReservedDuringAdjacentHandoff() async throws {
        let currentID = UUID()
        let nextID = UUID()
        let currentURL = try #require(URL(string: "https://example.com/current.png"))
        let nextURL = try #require(URL(string: "https://example.com/next.png"))
        let articleQueryService = PrefetchArticleQueryService(
            articlesByID: [
                currentID: makeReaderArticleDTO(id: currentID, imageURL: currentURL.absoluteString),
                nextID: makeReaderArticleDTO(id: nextID, imageURL: nextURL.absoluteString)
            ]
        )

        let plan = try ReaderAdjacentArticleImagePrefetcher.plan(
            context: makeContext(
                currentArticleID: currentID,
                nextArticleID: nextID
            ),
            articleQueryService: articleQueryService
        )

        #expect(plan.currentImageURL == currentURL)
        #expect(plan.adjacentImageURLs == [nextURL])
        #expect(plan.reservationURLs == [currentURL, nextURL])
    }

    @Test
    func prefetchedPreviousAndNextImagesAreConsumedWithoutAdditionalNetworkRequests() async throws {
        let previousID = UUID()
        let nextID = UUID()
        let previousURL = try #require(URL(string: "https://example.com/previous.png"))
        let nextURL = try #require(URL(string: "https://example.com/next.png"))
        let imageData = makePNGData(width: 80, height: 40)
        let httpClient = ScriptedHTTPClient(
            responsesByURL: [
                previousURL.absoluteString: .dataResponse(
                    statusCode: 200,
                    headers: ["Content-Type": "image/png"],
                    body: imageData
                ),
                nextURL.absoluteString: .dataResponse(
                    statusCode: 200,
                    headers: ["Content-Type": "image/png"],
                    body: imageData
                )
            ]
        )
        let memoryCache = ArticleImageMemoryCache(countLimit: 4, totalCostLimit: 4 * 1024 * 1024)
        let loader = ArticleImageLoader(
            httpClient: httpClient,
            memoryCache: memoryCache,
            diskCache: PrefetchDiscardingDiskCache()
        )
        let articleQueryService = PrefetchArticleQueryService(
            articlesByID: [
                previousID: makeReaderArticleDTO(id: previousID, imageURL: previousURL.absoluteString),
                nextID: makeReaderArticleDTO(id: nextID, imageURL: nextURL.absoluteString)
            ]
        )
        let context = makeContext(previousArticleID: previousID, nextArticleID: nextID)
        let coordinator = ReaderAdjacentArticleImagePrefetchCoordinator(imagePrefetcher: loader)

        coordinator.update(
            context: context,
            articleQueryService: articleQueryService
        )
        await waitUntilImageIsCached(memoryCache, url: previousURL)
        await waitUntilImageIsCached(memoryCache, url: nextURL)
        _ = try await loader.loadImage(from: previousURL, displayTarget: context.displayTarget)
        _ = try await loader.loadImage(from: nextURL, displayTarget: context.displayTarget)

        #expect(await httpClient.recordedRequests().count == 2)
        #expect(memoryCache.image(for: previousURL) != nil)
        #expect(memoryCache.image(for: nextURL) != nil)
    }

    @Test
    func twoStepWindowWarmsBothDirectionsAndCrossesArticleWithoutImage() async throws {
        let firstPreviousID = UUID()
        let secondPreviousID = UUID()
        let nextWithoutImageID = UUID()
        let firstNextImageID = UUID()
        let secondNextImageID = UUID()
        let imageURLs = try [
            #require(URL(string: "https://example.com/previous-near.png")),
            #require(URL(string: "https://example.com/previous-far.png")),
            #require(URL(string: "https://example.com/next-near.png")),
            #require(URL(string: "https://example.com/next-far.png"))
        ]
        let imageData = makePNGData(width: 80, height: 40)
        let responsesByURL = Dictionary(uniqueKeysWithValues: imageURLs.map { imageURL in
            (
                imageURL.absoluteString,
                ScriptedHTTPClient.Step.dataResponse(
                    statusCode: 200,
                    headers: ["Content-Type": "image/png"],
                    body: imageData
                )
            )
        })
        let httpClient = ScriptedHTTPClient(responsesByURL: responsesByURL)
        let memoryCache = ArticleImageMemoryCache(countLimit: 6, totalCostLimit: 4 * 1024 * 1024)
        let loader = ArticleImageLoader(
            httpClient: httpClient,
            memoryCache: memoryCache,
            diskCache: PrefetchDiscardingDiskCache()
        )
        let articleQueryService = PrefetchArticleQueryService(
            articlesByID: [
                firstPreviousID: makeReaderArticleDTO(
                    id: firstPreviousID,
                    imageURL: imageURLs[0].absoluteString
                ),
                secondPreviousID: makeReaderArticleDTO(
                    id: secondPreviousID,
                    imageURL: imageURLs[1].absoluteString
                ),
                nextWithoutImageID: makeReaderArticleDTO(id: nextWithoutImageID),
                firstNextImageID: makeReaderArticleDTO(
                    id: firstNextImageID,
                    imageURL: imageURLs[2].absoluteString
                ),
                secondNextImageID: makeReaderArticleDTO(
                    id: secondNextImageID,
                    imageURL: imageURLs[3].absoluteString
                )
            ]
        )
        let context = makeContext(
            previousCandidateArticleIDs: [firstPreviousID, secondPreviousID],
            nextCandidateArticleIDs: [nextWithoutImageID, firstNextImageID, secondNextImageID]
        )
        let coordinator = ReaderAdjacentArticleImagePrefetchCoordinator(imagePrefetcher: loader)

        coordinator.update(
            context: context,
            articleQueryService: articleQueryService
        )
        for imageURL in imageURLs {
            await waitUntilImageIsCached(memoryCache, url: imageURL)
            _ = try await loader.loadImage(from: imageURL, displayTarget: context.displayTarget)
        }

        #expect(await httpClient.recordedRequests().map(\.url).count == 4)
        #expect(imageURLs.allSatisfy { memoryCache.image(for: $0) != nil })
    }

    @Test
    func coordinatorLimitsConcurrentAdjacentImagePrefetches() async throws {
        let articleIDs = [UUID(), UUID(), UUID(), UUID()]
        let imageURLs = try (0..<4).map { index in
            try #require(URL(string: "https://example.com/concurrency-\(index).png"))
        }
        let imageData = makePNGData(width: 80, height: 40)
        let responseGate = ScriptedHTTPClientResponseGate()
        let httpClient = ScriptedHTTPClient(
            responsesByURL: Dictionary(uniqueKeysWithValues: imageURLs.map { imageURL in
                (
                    imageURL.absoluteString,
                    ScriptedHTTPClient.Step.gatedDataResponse(
                        statusCode: 200,
                        headers: ["Content-Type": "image/png"],
                        body: imageData,
                        gate: responseGate
                    )
                )
            })
        )
        let memoryCache = ArticleImageMemoryCache(countLimit: 6, totalCostLimit: 4 * 1024 * 1024)
        let loader = ArticleImageLoader(
            httpClient: httpClient,
            memoryCache: memoryCache,
            diskCache: PrefetchDiscardingDiskCache()
        )
        let articleQueryService = PrefetchArticleQueryService(
            articlesByID: Dictionary(uniqueKeysWithValues: zip(articleIDs, imageURLs).map {
                ($0.0, makeReaderArticleDTO(id: $0.0, imageURL: $0.1.absoluteString))
            })
        )
        let coordinator = ReaderAdjacentArticleImagePrefetchCoordinator(imagePrefetcher: loader)

        coordinator.update(
            context: makeContext(
                previousCandidateArticleIDs: Array(articleIDs.prefix(2)),
                nextCandidateArticleIDs: Array(articleIDs.suffix(2))
            ),
            articleQueryService: articleQueryService
        )
        await waitUntilGate(responseGate, reachesEntryCount: 2)

        #expect(await httpClient.maxConcurrentExecutions() == 2)

        await responseGate.release()
        for imageURL in imageURLs {
            await waitUntilImageIsCached(memoryCache, url: imageURL)
        }

        #expect(await httpClient.maxConcurrentExecutions() == 2)
    }

    @Test
    func existingSufficientMemoryEntryMakesPrefetchANetworkNoOp() async throws {
        let nextID = UUID()
        let imageURL = try #require(URL(string: "https://example.com/already-cached.png"))
        let httpClient = ScriptedHTTPClient()
        let memoryCache = ArticleImageMemoryCache(countLimit: 2, totalCostLimit: 1024 * 1024)
        memoryCache.insert(makeImage(width: 320, height: 160), for: imageURL)
        let loader = ArticleImageLoader(
            httpClient: httpClient,
            memoryCache: memoryCache,
            diskCache: PrefetchDiscardingDiskCache()
        )
        let articleQueryService = PrefetchArticleQueryService(
            articlesByID: [nextID: makeReaderArticleDTO(id: nextID, imageURL: imageURL.absoluteString)]
        )
        let coordinator = ReaderAdjacentArticleImagePrefetchCoordinator(imagePrefetcher: loader)

        coordinator.update(
            context: makeContext(nextArticleID: nextID),
            articleQueryService: articleQueryService
        )
        await Task.yield()

        #expect(await httpClient.recordedRequests().isEmpty)
    }

    @Test
    func failedPrefetchIsSilentAndDoesNotPopulateMemoryCache() async throws {
        let nextID = UUID()
        let imageURL = try #require(URL(string: "https://example.com/unavailable.png"))
        let httpClient = ScriptedHTTPClient(steps: [.urlError(.cannotConnectToHost)])
        let memoryCache = ArticleImageMemoryCache(countLimit: 2, totalCostLimit: 1024 * 1024)
        let loader = ArticleImageLoader(
            httpClient: httpClient,
            memoryCache: memoryCache,
            diskCache: PrefetchDiscardingDiskCache()
        )
        let articleQueryService = PrefetchArticleQueryService(
            articlesByID: [nextID: makeReaderArticleDTO(id: nextID, imageURL: imageURL.absoluteString)]
        )
        let coordinator = ReaderAdjacentArticleImagePrefetchCoordinator(imagePrefetcher: loader)

        coordinator.update(
            context: makeContext(nextArticleID: nextID),
            articleQueryService: articleQueryService
        )
        await waitUntilRequestStarts(httpClient)
        await waitUntilRequestsFinish(httpClient)

        #expect(await httpClient.recordedRequests().count == 1)
        #expect(memoryCache.image(for: imageURL) == nil)
    }

    @Test
    func cancellationStopsOldSessionPrefetchAndSessionGenerationChangesTaskIdentity() async throws {
        let nextID = UUID()
        let imageURL = try #require(URL(string: "https://example.com/slow.png"))
        let httpClient = ScriptedHTTPClient(
            steps: [
                .delayedResponse(
                    statusCode: 200,
                    headers: ["Content-Type": "image/png"],
                    body: "not-reached",
                    delayNanoseconds: 5_000_000_000
                )
            ]
        )
        let memoryCache = ArticleImageMemoryCache(countLimit: 2, totalCostLimit: 1024 * 1024)
        let loader = ArticleImageLoader(
            httpClient: httpClient,
            memoryCache: memoryCache,
            diskCache: PrefetchDiscardingDiskCache()
        )
        let articleQueryService = PrefetchArticleQueryService(
            articlesByID: [nextID: makeReaderArticleDTO(id: nextID, imageURL: imageURL.absoluteString)]
        )
        let oldContext = makeContext(articleListSessionID: UUID(), nextArticleID: nextID)
        let newContext = makeContext(articleListSessionID: UUID(), nextArticleID: nextID)
        let coordinator = ReaderAdjacentArticleImagePrefetchCoordinator(imagePrefetcher: loader)

        #expect(oldContext != newContext)

        coordinator.update(
            context: oldContext,
            articleQueryService: articleQueryService
        )
        await waitUntilRequestStarts(httpClient)
        coordinator.clear()
        await Task.yield()
        await waitUntilRequestsFinish(httpClient)

        #expect(await httpClient.currentInFlightExecutionCount() == 0)
        #expect(memoryCache.image(for: imageURL) == nil)
    }

    @Test
    func repeatedReaderPresentationKeepsSameSessionPrefetchAlive() async throws {
        let nextID = UUID()
        let imageURL = try #require(URL(string: "https://example.com/repeated-reader.png"))
        let imageData = makePNGData(width: 80, height: 40)
        let responseGate = ScriptedHTTPClientResponseGate()
        let httpClient = ScriptedHTTPClient(
            steps: [
                .gatedDataResponse(
                    statusCode: 200,
                    headers: ["Content-Type": "image/png"],
                    body: imageData,
                    gate: responseGate
                )
            ]
        )
        let memoryCache = ArticleImageMemoryCache(countLimit: 2, totalCostLimit: 1024 * 1024)
        let loader = ArticleImageLoader(
            httpClient: httpClient,
            memoryCache: memoryCache,
            diskCache: PrefetchDiscardingDiskCache()
        )
        let articleQueryService = PrefetchArticleQueryService(
            articlesByID: [nextID: makeReaderArticleDTO(id: nextID, imageURL: imageURL.absoluteString)]
        )
        let context = makeContext(articleListSessionID: UUID(), nextArticleID: nextID)
        let coordinator = ReaderAdjacentArticleImagePrefetchCoordinator(imagePrefetcher: loader)

        coordinator.update(
            context: context,
            articleQueryService: articleQueryService
        )
        await waitUntilRequestStarts(httpClient)

        coordinator.update(
            context: context,
            articleQueryService: articleQueryService
        )
        await responseGate.release()
        await waitUntilRequestsFinish(httpClient)
        await waitUntilImageIsCached(memoryCache, url: imageURL)

        #expect(await httpClient.recordedRequests().count == 1)
        #expect(memoryCache.image(for: imageURL) != nil)
    }

    @Test
    func coordinatorRollsPrefetchWindowAfterCurrentArticleChanges() async throws {
        let firstID = UUID()
        let secondID = UUID()
        let thirdID = UUID()
        let secondURL = try #require(URL(string: "https://example.com/second.png"))
        let thirdURL = try #require(URL(string: "https://example.com/third.png"))
        let imageData = makePNGData(width: 80, height: 40)
        let httpClient = ScriptedHTTPClient(
            responsesByURL: [
                secondURL.absoluteString: .dataResponse(
                    statusCode: 200,
                    headers: ["Content-Type": "image/png"],
                    body: imageData
                ),
                thirdURL.absoluteString: .dataResponse(
                    statusCode: 200,
                    headers: ["Content-Type": "image/png"],
                    body: imageData
                )
            ]
        )
        let memoryCache = ArticleImageMemoryCache(countLimit: 3, totalCostLimit: 1024 * 1024)
        let loader = ArticleImageLoader(
            httpClient: httpClient,
            memoryCache: memoryCache,
            diskCache: PrefetchDiscardingDiskCache()
        )
        let articleQueryService = PrefetchArticleQueryService(
            articlesByID: [
                firstID: makeReaderArticleDTO(id: firstID),
                secondID: makeReaderArticleDTO(id: secondID, imageURL: secondURL.absoluteString),
                thirdID: makeReaderArticleDTO(id: thirdID, imageURL: thirdURL.absoluteString)
            ]
        )
        let sessionID = UUID()
        let coordinator = ReaderAdjacentArticleImagePrefetchCoordinator(imagePrefetcher: loader)

        coordinator.update(
            context: makeContext(
                currentArticleID: firstID,
                articleListSessionID: sessionID,
                nextArticleID: secondID
            ),
            articleQueryService: articleQueryService
        )
        await waitUntilImageIsCached(memoryCache, url: secondURL)

        coordinator.update(
            context: makeContext(
                currentArticleID: secondID,
                articleListSessionID: sessionID,
                previousArticleID: firstID,
                nextArticleID: thirdID
            ),
            articleQueryService: articleQueryService
        )
        await waitUntilImageIsCached(memoryCache, url: thirdURL)

        let requestedURLs = await httpClient.recordedRequests().map(\.url)
        #expect(requestedURLs == [secondURL, thirdURL])
        #expect(memoryCache.image(for: secondURL) != nil)
        #expect(memoryCache.image(for: thirdURL) != nil)
    }

    @Test
    func rollingCoordinatorReservationKeepsPrefetchedTargetWhenItBecomesCurrent() async throws {
        let firstID = UUID()
        let secondID = UUID()
        let thirdID = UUID()
        let secondURL = try #require(URL(string: "https://example.com/reserved-second.png"))
        let thirdURL = try #require(URL(string: "https://example.com/reserved-third.png"))
        let articleQueryService = PrefetchArticleQueryService(
            articlesByID: [
                firstID: makeReaderArticleDTO(id: firstID),
                secondID: makeReaderArticleDTO(id: secondID, imageURL: secondURL.absoluteString),
                thirdID: makeReaderArticleDTO(id: thirdID, imageURL: thirdURL.absoluteString)
            ]
        )
        let imagePrefetcher = RecordingArticleImagePrefetcher()
        let coordinator = ReaderAdjacentArticleImagePrefetchCoordinator(
            imagePrefetcher: imagePrefetcher
        )
        let sessionID = UUID()

        coordinator.update(
            context: makeContext(
                currentArticleID: firstID,
                articleListSessionID: sessionID,
                nextArticleID: secondID
            ),
            articleQueryService: articleQueryService
        )
        await Task.yield()
        coordinator.update(
            context: makeContext(
                currentArticleID: secondID,
                articleListSessionID: sessionID,
                previousArticleID: firstID,
                nextArticleID: thirdID
            ),
            articleQueryService: articleQueryService
        )

        #expect(imagePrefetcher.reservationWindows == [
            [secondURL],
            [secondURL, thirdURL]
        ])
    }

    @Test
    func clearingReaderRouteClearsPrefetchScope() async throws {
        let nextID = UUID()
        let imageURL = try #require(URL(string: "https://example.com/release.png"))
        let articleQueryService = PrefetchArticleQueryService(
            articlesByID: [
                nextID: makeReaderArticleDTO(id: nextID, imageURL: imageURL.absoluteString)
            ]
        )
        let imagePrefetcher = RecordingArticleImagePrefetcher()
        let coordinator = ReaderAdjacentArticleImagePrefetchCoordinator(
            imagePrefetcher: imagePrefetcher
        )

        coordinator.update(
            context: makeContext(nextArticleID: nextID),
            articleQueryService: articleQueryService
        )
        coordinator.clear()
        await Task.yield()
        await Task.yield()

        #expect(imagePrefetcher.clearReservationCount == 1)
    }

    @Test
    func reopeningReaderInSameSessionRestartsPrefetchAfterRouteCleanup() async throws {
        let firstArticleID = UUID()
        let secondArticleID = UUID()
        let firstNextID = UUID()
        let secondNextID = UUID()
        let firstURL = try #require(URL(string: "https://example.com/reopen-first.png"))
        let secondURL = try #require(URL(string: "https://example.com/reopen-second.png"))
        let articleQueryService = PrefetchArticleQueryService(
            articlesByID: [
                firstNextID: makeReaderArticleDTO(id: firstNextID, imageURL: firstURL.absoluteString),
                secondNextID: makeReaderArticleDTO(id: secondNextID, imageURL: secondURL.absoluteString)
            ]
        )
        let imagePrefetcher = RecordingArticleImagePrefetcher()
        let coordinator = ReaderAdjacentArticleImagePrefetchCoordinator(
            imagePrefetcher: imagePrefetcher
        )
        let sessionID = UUID()

        coordinator.update(
            context: makeContext(
                currentArticleID: firstArticleID,
                articleListSessionID: sessionID,
                nextArticleID: firstNextID
            ),
            articleQueryService: articleQueryService
        )
        await Task.yield()
        coordinator.clear()
        coordinator.update(
            context: makeContext(
                currentArticleID: secondArticleID,
                articleListSessionID: sessionID,
                nextArticleID: secondNextID
            ),
            articleQueryService: articleQueryService
        )
        await Task.yield()
        await Task.yield()

        #expect(imagePrefetcher.clearReservationCount == 1)
        #expect(imagePrefetcher.requestedURLs.contains(firstURL))
        #expect(imagePrefetcher.requestedURLs.contains(secondURL))
        #expect(imagePrefetcher.reservationWindows.last == [secondURL])
    }

    @Test
    func rollingContextKeepsOldTargetLoadAliveUntilVisibleReaderJoins() async throws {
        let firstID = UUID()
        let secondID = UUID()
        let thirdID = UUID()
        let secondURL = try #require(URL(string: "https://example.com/rolling-second.png"))
        let thirdURL = try #require(URL(string: "https://example.com/rolling-third.png"))
        let imageData = makePNGData(width: 80, height: 40)
        let secondResponseGate = ScriptedHTTPClientResponseGate()
        let httpClient = ScriptedHTTPClient(
            responsesByURL: [
                secondURL.absoluteString: .gatedDataResponse(
                    statusCode: 200,
                    headers: ["Content-Type": "image/png"],
                    body: imageData,
                    gate: secondResponseGate
                ),
                thirdURL.absoluteString: .dataResponse(
                    statusCode: 200,
                    headers: ["Content-Type": "image/png"],
                    body: imageData
                )
            ]
        )
        let memoryCache = ArticleImageMemoryCache(countLimit: 6, totalCostLimit: 1024 * 1024)
        let loader = ArticleImageLoader(
            httpClient: httpClient,
            memoryCache: memoryCache,
            diskCache: PrefetchDiscardingDiskCache()
        )
        let articleQueryService = PrefetchArticleQueryService(
            articlesByID: [
                firstID: makeReaderArticleDTO(id: firstID),
                secondID: makeReaderArticleDTO(id: secondID, imageURL: secondURL.absoluteString),
                thirdID: makeReaderArticleDTO(id: thirdID, imageURL: thirdURL.absoluteString)
            ]
        )
        let sessionID = UUID()
        let coordinator = ReaderAdjacentArticleImagePrefetchCoordinator(imagePrefetcher: loader)

        coordinator.update(
            context: makeContext(
                currentArticleID: firstID,
                articleListSessionID: sessionID,
                nextArticleID: secondID
            ),
            articleQueryService: articleQueryService
        )
        await waitUntilRequestStarts(httpClient)

        coordinator.update(
            context: makeContext(
                currentArticleID: secondID,
                articleListSessionID: sessionID,
                previousArticleID: firstID,
                nextArticleID: thirdID
            ),
            articleQueryService: articleQueryService
        )
        let visibleLoad = Task { @MainActor in
            try await loader.loadImage(from: secondURL, displayTarget: makeContext().displayTarget)
        }
        await secondResponseGate.release()
        _ = try await visibleLoad.value
        await waitUntilImageIsCached(memoryCache, url: thirdURL)

        let requestedURLs = await httpClient.recordedRequests().map(\.url)
        #expect(requestedURLs.count == 2)
        #expect(Set(requestedURLs) == [secondURL, thirdURL])
        #expect(memoryCache.image(for: secondURL) != nil)
        #expect(memoryCache.image(for: thirdURL) != nil)
    }

    @Test
    func newListSessionCancelsOldPrefetchScope() async throws {
        let oldNextID = UUID()
        let newNextID = UUID()
        let oldURL = try #require(URL(string: "https://example.com/old-session.png"))
        let newURL = try #require(URL(string: "https://example.com/new-session.png"))
        let imageData = makePNGData(width: 80, height: 40)
        let oldResponseGate = ScriptedHTTPClientResponseGate()
        let httpClient = ScriptedHTTPClient(
            responsesByURL: [
                oldURL.absoluteString: .gatedDataResponse(
                    statusCode: 200,
                    headers: ["Content-Type": "image/png"],
                    body: imageData,
                    gate: oldResponseGate
                ),
                newURL.absoluteString: .dataResponse(
                    statusCode: 200,
                    headers: ["Content-Type": "image/png"],
                    body: imageData
                )
            ]
        )
        let memoryCache = ArticleImageMemoryCache(countLimit: 6, totalCostLimit: 1024 * 1024)
        let loader = ArticleImageLoader(
            httpClient: httpClient,
            memoryCache: memoryCache,
            diskCache: PrefetchDiscardingDiskCache()
        )
        let articleQueryService = PrefetchArticleQueryService(
            articlesByID: [
                oldNextID: makeReaderArticleDTO(id: oldNextID, imageURL: oldURL.absoluteString),
                newNextID: makeReaderArticleDTO(id: newNextID, imageURL: newURL.absoluteString)
            ]
        )
        let coordinator = ReaderAdjacentArticleImagePrefetchCoordinator(imagePrefetcher: loader)

        coordinator.update(
            context: makeContext(articleListSessionID: UUID(), nextArticleID: oldNextID),
            articleQueryService: articleQueryService
        )
        await waitUntilRequestStarts(httpClient)

        coordinator.update(
            context: makeContext(articleListSessionID: UUID(), nextArticleID: newNextID),
            articleQueryService: articleQueryService
        )
        await oldResponseGate.release()
        await waitUntilRequestsFinish(httpClient)
        await waitUntilImageIsCached(memoryCache, url: newURL)

        #expect(memoryCache.image(for: oldURL) == nil)
        #expect(memoryCache.image(for: newURL) != nil)
    }

    private func makeContext(
        currentArticleID: UUID = UUID(),
        articleListSessionID: UUID = UUID(),
        previousArticleID: UUID? = nil,
        nextArticleID: UUID? = nil,
        previousCandidateArticleIDs: [UUID]? = nil,
        nextCandidateArticleIDs: [UUID]? = nil
    ) -> ReaderAdjacentArticleImagePrefetchContext {
        ReaderAdjacentArticleImagePrefetchContext(
            currentArticleID: currentArticleID,
            articleListSessionID: articleListSessionID,
            previousCandidateArticleIDs: previousCandidateArticleIDs
                ?? previousArticleID.map { [$0] }
                ?? [],
            nextCandidateArticleIDs: nextCandidateArticleIDs
                ?? nextArticleID.map { [$0] }
                ?? [],
            displayTarget: ArticleImageDisplayTarget(maximumPixelWidth: 320)
        )
    }

    private func makePNGData(width: Int, height: Int) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height),
            format: format
        ).pngData { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    private func makeImage(width: Int, height: Int) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height),
            format: format
        ).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    private func waitUntilRequestStarts(_ httpClient: ScriptedHTTPClient) async {
        for _ in 0..<1_000 {
            if await httpClient.currentInFlightExecutionCount() > 0 {
                return
            }
            await Task.yield()
        }
    }

    private func waitUntilRequestsFinish(_ httpClient: ScriptedHTTPClient) async {
        for _ in 0..<1_000 {
            if await httpClient.currentInFlightExecutionCount() == 0 {
                return
            }
            await Task.yield()
        }
    }

    private func waitUntilImageIsCached(_ cache: ArticleImageMemoryCache, url: URL) async {
        for _ in 0..<1_000 {
            if cache.image(for: url) != nil {
                return
            }
            await Task.yield()
        }
    }

    private func waitUntilGate(
        _ gate: ScriptedHTTPClientResponseGate,
        reachesEntryCount expectedCount: Int
    ) async {
        for _ in 0..<1_000 {
            if await gate.enteredCount() >= expectedCount {
                return
            }
            await Task.yield()
        }
    }
}

@MainActor
private final class PrefetchArticleQueryService: ArticleQueryService {
    private let articlesByID: [UUID: ReaderArticleDTO]
    private(set) var requestedArticleIDs: [UUID] = []

    init(articlesByID: [UUID: ReaderArticleDTO]) {
        self.articlesByID = articlesByID
    }

    func fetchArticleSearchSnapshot(
        _ request: ArticleSearchRequest
    ) async throws -> ArticleSearchResultSnapshot {
        fatalError("Search is not used by adjacent image prefetch tests")
    }

    func fetchReaderArticle(id: UUID) throws -> ReaderArticleDTO? {
        requestedArticleIDs.append(id)
        return articlesByID[id]
    }

    func fetchReaderArticles(ids: [UUID]) throws -> [ReaderArticleDTO] {
        requestedArticleIDs.append(contentsOf: ids)
        return ids.compactMap { articlesByID[$0] }
    }
}

@MainActor
private final class RecordingArticleImagePrefetcher: ArticleImagePrefetching {
    private(set) var requestedURLs: [URL] = []
    private(set) var displayTargets: [ArticleImageDisplayTarget] = []
    private(set) var reservationWindows: [[URL]] = []
    private(set) var clearReservationCount = 0

    func prefetchImage(from url: URL, displayTarget: ArticleImageDisplayTarget) async {
        requestedURLs.append(url)
        displayTargets.append(displayTarget)
    }

    func replacePrefetchReservations(with urls: [URL]) {
        reservationWindows.append(urls)
    }

    func clearPrefetchReservations() {
        clearReservationCount += 1
    }
}

private actor PrefetchDiscardingDiskCache: ArticleImageDiskCaching {
    func data(for url: URL) -> Data? { nil }
    func data(for url: URL, maximumBytes: Int64) -> Data? { nil }
    func insert(_ data: Data, for url: URL) {}
    func removeData(for url: URL) {}
}
