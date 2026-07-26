import Foundation
import Testing
import UIKit
@testable import RSSReader

@Suite("Feeds / Feed Icon Discovery")
@MainActor
struct FeedIconDiscoveryServiceTests {
    @Test
    func discoveryUsesCachedRasterIconWithoutNetworkRequest() async throws {
        let iconURL = try makeURL("https://example.com/cached-icon.png")
        let iconData = makePNGData()
        let service = try makeService(responsesByURL: [:])
        try await service.feedIconCache.storeImageData(iconData, for: iconURL)

        let discoveredURL = try await service.discoveryService.discoverIconURL(
            feedURL: try makeURL("https://example.com/feed.xml"),
            siteURL: nil,
            metadataIconURL: iconURL
        )

        #expect(discoveredURL == iconURL)
        #expect(await service.httpClient.recordedRequests().isEmpty)
    }

    @Test
    func discoveryRejectsOversizedIconBeforeCacheStorage() async throws {
        let iconURL = try makeURL("https://example.com/oversized-icon.png")
        let budget = AppResourceBudgetContract.current.feedIcon.body
        let service = try makeService(
            responsesByURL: [
                iconURL.absoluteString: .dataResponse(
                    statusCode: 200,
                    headers: ["Content-Type": "image/png"],
                    body: Data(repeating: 0, count: Int(budget.maximumCompressedBodyBytes + 1))
                )
            ]
        )

        let discoveredURL = try await service.discoveryService.discoverIconURL(
            feedURL: try makeURL("https://example.com/feed.xml"),
            siteURL: nil,
            metadataIconURL: iconURL
        )

        #expect(discoveredURL == nil)
        #expect(try await service.feedIconCache.cachedImageData(for: iconURL) == nil)
        let request = try #require(await service.httpClient.recordedRequests().first)
        #expect(request.maximumResponseBodyBytes == budget.maximumCompressedBodyBytes)
    }

    @Test
    func discoveryRejectsUnsupportedIconMIMEBeforeImageDecodeOrCache() async throws {
        let iconURL = try makeURL("https://example.com/wrong-mime.png")
        let service = try makeService(
            responsesByURL: [
                iconURL.absoluteString: .dataResponse(
                    statusCode: 200,
                    headers: ["Content-Type": "text/html"],
                    body: makePNGData()
                )
            ]
        )

        let discoveredURL = try await service.discoveryService.discoverIconURL(
            feedURL: try makeURL("https://example.com/feed.xml"),
            siteURL: nil,
            metadataIconURL: iconURL
        )

        #expect(discoveredURL == nil)
        #expect(try await service.feedIconCache.cachedImageData(for: iconURL) == nil)
        let request = try #require(await service.httpClient.recordedRequests().first)
        #expect(
            request.maximumResponseBodyBytes
                == AppResourceBudgetContract.current.feedIcon.body.maximumCompressedBodyBytes
        )
    }

    @Test
    func discoveryUsesMetadataIconURLWhenItContainsRasterImage() async throws {
        let iconURL = try makeURL("https://example.com/feed-icon.png")
        let service = try makeService(
            responsesByURL: [
                iconURL.absoluteString: .dataResponse(
                    statusCode: 200,
                    headers: ["Content-Type": "image/png"],
                    body: makePNGData()
                )
            ]
        )

        let discoveredURL = try await service.discoveryService.discoverIconURL(
            feedURL: try makeURL("https://example.com/feed.xml"),
            siteURL: try makeURL("https://example.com/"),
            metadataIconURL: iconURL
        )

        #expect(discoveredURL == iconURL)
        #expect(try await service.feedIconCache.cachedImageData(for: iconURL) != nil)

        let requests = await service.httpClient.recordedRequests()
        #expect(requests.map(\.url.absoluteString) == [iconURL.absoluteString])
        #expect(requests.allSatisfy { $0.timeoutInterval <= 2 })
    }

    @Test
    func discoveryPropagatesCancellationFromIconCandidateRequest() async throws {
        let iconURL = try makeURL("https://example.com/cancelled-icon.png")
        let service = try makeService(
            responsesByURL: [
                iconURL.absoluteString: .cancelled
            ]
        )

        await #expect(throws: CancellationError.self) {
            try await service.discoveryService.discoverIconURL(
                feedURL: try makeURL("https://example.com/feed.xml"),
                siteURL: nil,
                metadataIconURL: iconURL
            )
        }
    }

    @Test
    func discoveryPropagatesCancellationFromHomepageRequest() async throws {
        let homeURL = try makeURL("https://example.com/")
        let commonURLs = FeedIconCandidateBuilder.commonIconCandidates(for: homeURL)
        let commonResponses = Dictionary(
            uniqueKeysWithValues: commonURLs.map { url in
                (
                    url.absoluteString,
                    ScriptedHTTPClient.Step.response(
                        statusCode: 404,
                        headers: ["Content-Type": "text/plain"],
                        body: ""
                    )
                )
            }
        )
        let service = try makeService(
            responsesByURL: commonResponses.merging(
                [homeURL.absoluteString: .cancelled],
                uniquingKeysWith: { _, rhs in rhs }
            )
        )

        await #expect(throws: CancellationError.self) {
            try await service.discoveryService.discoverIconURL(
                feedURL: try makeURL("https://example.com/feed.xml"),
                siteURL: homeURL,
                metadataIconURL: nil
            )
        }

        let requests = await service.httpClient.recordedRequests()
        #expect(requests.map(\.url.absoluteString) == commonURLs.map(\.absoluteString) + [homeURL.absoluteString])
    }

    @Test
    func discoveryFallsBackToCommonFaviconPathsBeforeHTML() async throws {
        let iconURL = try makeURL("https://example.com/apple-touch-icon.png")
        let service = try makeService(
            responsesByURL: [
                iconURL.absoluteString: .dataResponse(
                    statusCode: 200,
                    headers: ["Content-Type": "image/png"],
                    body: makePNGData()
                )
            ]
        )

        let discoveredURL = try await service.discoveryService.discoverIconURL(
            feedURL: try makeURL("https://example.com/feed.xml"),
            siteURL: try makeURL("https://example.com/"),
            metadataIconURL: nil
        )

        #expect(discoveredURL == iconURL)
        #expect(try await service.feedIconCache.cachedImageData(for: iconURL) != nil)

        let requests = await service.httpClient.recordedRequests()
        #expect(requests.map(\.url.absoluteString) == [iconURL.absoluteString])
        #expect(requests.allSatisfy { $0.timeoutInterval <= 2 })
    }

    @Test
    func discoveryUsesHTMLLinkIconAfterCommonPathsFail() async throws {
        let htmlURL = try makeURL("https://example.com/")
        let linkedIconURL = try makeURL("https://example.com/assets/favicon.png")
        let commonURLs = FeedIconCandidateBuilder.commonIconCandidates(for: htmlURL)
        let commonResponses = Dictionary(
            uniqueKeysWithValues: commonURLs.map { url in
                (
                    url.absoluteString,
                    ScriptedHTTPClient.Step.response(
                        statusCode: 404,
                        headers: ["Content-Type": "text/plain"],
                        body: ""
                    )
                )
            }
        )
        let service = try makeService(
            responsesByURL: commonResponses.merging(
                [
                    htmlURL.absoluteString: .response(
                        statusCode: 200,
                        headers: ["Content-Type": "text/html"],
                        body: """
                        <html><head>
                        <link rel="icon" href="/assets/favicon.png">
                        </head></html>
                        """
                    ),
                    linkedIconURL.absoluteString: .dataResponse(
                        statusCode: 200,
                        headers: ["Content-Type": "image/png"],
                        body: makePNGData()
                    )
                ],
                uniquingKeysWith: { _, rhs in rhs }
            )
        )

        let discoveredURL = try await service.discoveryService.discoverIconURL(
            feedURL: try makeURL("https://example.com/feed.xml"),
            siteURL: htmlURL,
            metadataIconURL: nil
        )

        #expect(discoveredURL == linkedIconURL)
        #expect(try await service.feedIconCache.cachedImageData(for: linkedIconURL) != nil)

        let requests = await service.httpClient.recordedRequests()
        #expect(requests.map(\.url.absoluteString) == commonURLs.map(\.absoluteString) + [
            htmlURL.absoluteString,
            linkedIconURL.absoluteString
        ])
        #expect(requests.allSatisfy { $0.timeoutInterval <= 2 })
    }

    @Test
    func discoveryResolvesRelativeHTMLIconLinksAgainstLoadedHTMLURL() async throws {
        let siteURL = try makeURL("https://example.com/blog/")
        let htmlURL = try makeURL("https://example.com/")
        let linkedIconURL = try makeURL("https://example.com/assets/favicon.png")
        let commonURLs = FeedIconCandidateBuilder.commonIconCandidates(for: htmlURL)
        let commonResponses = Dictionary(
            uniqueKeysWithValues: commonURLs.map { url in
                (
                    url.absoluteString,
                    ScriptedHTTPClient.Step.response(
                        statusCode: 404,
                        headers: ["Content-Type": "text/plain"],
                        body: ""
                    )
                )
            }
        )
        let service = try makeService(
            responsesByURL: commonResponses.merging(
                [
                    htmlURL.absoluteString: .response(
                        statusCode: 200,
                        headers: ["Content-Type": "text/html"],
                        body: """
                        <html><head>
                        <link rel="icon" href="assets/favicon.png">
                        </head></html>
                        """
                    ),
                    linkedIconURL.absoluteString: .dataResponse(
                        statusCode: 200,
                        headers: ["Content-Type": "image/png"],
                        body: makePNGData()
                    )
                ],
                uniquingKeysWith: { _, rhs in rhs }
            )
        )

        let discoveredURL = try await service.discoveryService.discoverIconURL(
            feedURL: try makeURL("https://example.com/feed.xml"),
            siteURL: siteURL,
            metadataIconURL: nil
        )

        #expect(discoveredURL == linkedIconURL)

        let requests = await service.httpClient.recordedRequests()
        #expect(requests.map(\.url.absoluteString) == commonURLs.map(\.absoluteString) + [
            htmlURL.absoluteString,
            linkedIconURL.absoluteString
        ])
        #expect(requests.allSatisfy { $0.timeoutInterval <= 2 })
    }

    @Test
    func candidateBuilderParsesHTMLIconLinksInPriorityOrder() throws {
        let baseURL = try makeURL("https://example.com/")
        let html = """
        <!doctype html>
        <html>
          <head>
            <link rel="icon" sizes="32x32" href="/favicon-32x32.png">
            <link rel="apple-touch-icon" sizes="180x180" href="/apple-touch-icon.png">
            <link rel="mask-icon" href="/mask.svg">
            <link rel="shortcut icon" href="/favicon.ico">
          </head>
          <body></body>
        </html>
        """

        let candidates = FeedIconCandidateBuilder.htmlIconCandidates(in: html, baseURL: baseURL)
            .map(\.absoluteString)

        #expect(candidates == [
            "https://example.com/apple-touch-icon.png",
            "https://example.com/favicon-32x32.png",
            "https://example.com/favicon.ico"
        ])
    }

    @Test
    func candidateBuilderBuildsCommonIconCandidatesFromOrigin() throws {
        let iconURL = try makeURL("https://example.com/news/favicon.ico")

        let candidates = FeedIconCandidateBuilder.commonIconCandidates(for: iconURL)
            .map(\.absoluteString)

        #expect(candidates == [
            "https://example.com/apple-touch-icon.png",
            "https://example.com/apple-touch-icon-precomposed.png",
            "https://example.com/favicon-32x32.png",
            "https://example.com/favicon.png",
            "https://example.com/favicon.ico"
        ])
    }

    @Test
    func imagePolicyRejectsWideLogoImages() {
        #expect(FeedIconImagePolicy.isSuitableIconSize(CGSize(width: 180, height: 180)))
        #expect(FeedIconImagePolicy.isSuitableIconSize(CGSize(width: 64, height: 32)))
        #expect(FeedIconImagePolicy.isSuitableIconSize(CGSize(width: 240, height: 40)) == false)
        #expect(FeedIconImagePolicy.isSuitableIconSize(CGSize(width: 0, height: 0)) == false)
    }

    @Test
    func imagePolicyRejectsRasterDimensionsOverFeedIconBudget() {
        let oversizedData = makePNGData(size: CGSize(width: 1_025, height: 1_024))

        #expect(FeedIconImagePolicy.isSuitableRasterIcon(oversizedData) == false)
    }

    private func makeService(
        responsesByURL: [String: ScriptedHTTPClient.Step]
    ) throws -> FeedIconDiscoveryServiceHarness {
        let directoryURL = try makeTemporaryDirectory()
        let diskCache = FeedIconDiskCache(directoryURL: directoryURL, capacityLimit: 1_024 * 1_024)
        let httpClient = ScriptedHTTPClient(responsesByURL: responsesByURL)
        let feedIconCache = FeedIconCacheService(diskCache: diskCache)
        let discoveryService = FeedIconDiscoveryService(
            logger: TestLogger(),
            httpClient: httpClient,
            feedIconCache: feedIconCache,
            discoveryBudgetInterval: 60
        )

        return FeedIconDiscoveryServiceHarness(
            discoveryService: discoveryService,
            feedIconCache: feedIconCache,
            httpClient: httpClient,
            directoryURL: directoryURL
        )
    }

    private func makeURL(_ string: String) throws -> URL {
        try #require(URL(string: string))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        return directoryURL
    }

    private func makePNGData(size: CGSize = CGSize(width: 16, height: 16)) -> Data {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.pngData { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}

private final class FeedIconDiscoveryServiceHarness {
    let discoveryService: FeedIconDiscoveryService
    let feedIconCache: FeedIconCacheService
    let httpClient: ScriptedHTTPClient
    let directoryURL: URL

    init(
        discoveryService: FeedIconDiscoveryService,
        feedIconCache: FeedIconCacheService,
        httpClient: ScriptedHTTPClient,
        directoryURL: URL
    ) {
        self.discoveryService = discoveryService
        self.feedIconCache = feedIconCache
        self.httpClient = httpClient
        self.directoryURL = directoryURL
    }

    deinit {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}
