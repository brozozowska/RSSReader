import Foundation
import Testing
import UIKit
@testable import RSSReader

@Suite("Article Screen / Bounded Article Image Loader")
@MainActor
struct ArticleImageLoaderTests {
    @Test
    func articleImageRequestConfigurationBypassesSharedURLCache() {
        let configuration = URLSessionConfiguration.articleImageRequestsDefault()

        #expect(configuration.urlCache == nil)
        #expect(configuration.requestCachePolicy == .reloadIgnoringLocalCacheData)
    }

    @Test
    func coldLoadFetchesValidatedImageAndPopulatesCustomCaches() async throws {
        let imageURL = try #require(URL(string: "https://example.com/images/large.png"))
        let imageData = makePNGData(width: 120, height: 60)
        let fixture = try makeFixture(
            steps: [
                .dataResponse(
                    statusCode: 200,
                    headers: ["Content-Type": "image/png"],
                    body: imageData
                )
            ]
        )
        defer { fixture.removeTemporaryDirectory() }

        let image = try await fixture.loader.loadImage(
            from: imageURL,
            displayTarget: ArticleImageDisplayTarget(maximumPixelWidth: 24)
        )

        let cgImage = try #require(image.cgImage)
        let cachedDecodedByteCost = try #require(
            fixture.memoryCache.cachedDecodedByteCost(for: imageURL)
        )
        #expect(cgImage.width <= 24)
        #expect(cgImage.height <= 12)
        #expect(cachedDecodedByteCost == cgImage.bytesPerRow * cgImage.height)
        #expect(cachedDecodedByteCost != imageData.count)
        #expect(fixture.memoryCache.image(for: imageURL) === image)
        #expect(try await fixture.diskCache.data(for: imageURL) == imageData)

        let request = try #require(await fixture.httpClient.recordedRequests().first)
        #expect(
            request.maximumResponseBodyBytes
                == AppResourceBudgetContract.current.articleImage.body.maximumCompressedBodyBytes
        )
    }

    @Test
    func diskWriteFailureKeepsValidatedArticleImageAvailableInMemory() async throws {
        let rootDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: rootDirectoryURL,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: rootDirectoryURL) }

        let blockingFileURL = rootDirectoryURL.appendingPathComponent("not-a-directory")
        let blockingData = Data("blocking-file".utf8)
        try blockingData.write(to: blockingFileURL)

        let imageURL = try #require(URL(string: "https://example.com/images/write-failure.png"))
        let imageData = makePNGData(width: 48, height: 24)
        let httpClient = ScriptedHTTPClient(
            steps: [
                .dataResponse(
                    statusCode: 200,
                    headers: ["Content-Type": "image/png"],
                    body: imageData
                )
            ]
        )
        let memoryCache = ArticleImageMemoryCache(
            countLimit: 2,
            totalCostLimit: 4 * 1024 * 1024
        )
        let diskCache = ArticleImageDiskCache(
            directoryURL: blockingFileURL,
            capacityLimit: 4 * 1024 * 1024
        )
        let loader = ArticleImageLoader(
            httpClient: httpClient,
            memoryCache: memoryCache,
            diskCache: diskCache
        )

        let image = try await loader.loadImage(
            from: imageURL,
            displayTarget: ArticleImageDisplayTarget(maximumPixelWidth: 24)
        )

        #expect(memoryCache.image(for: imageURL) === image)
        #expect(try await diskCache.data(for: imageURL) == nil)
        #expect(try Data(contentsOf: blockingFileURL) == blockingData)
        #expect(await httpClient.recordedRequests().count == 1)
    }

    @Test
    func warmLoadUsesDecodedMemoryCacheWithoutSecondNetworkRequest() async throws {
        let imageURL = try #require(URL(string: "https://example.com/images/warm.png"))
        let imageData = makePNGData(width: 64, height: 32)
        let fixture = try makeFixture(
            steps: [
                .dataResponse(
                    statusCode: 200,
                    headers: ["Content-Type": "image/png"],
                    body: imageData
                )
            ]
        )
        defer { fixture.removeTemporaryDirectory() }
        let displayTarget = ArticleImageDisplayTarget(maximumPixelWidth: 32)

        let coldImage = try await fixture.loader.loadImage(from: imageURL, displayTarget: displayTarget)
        let warmImage = try await fixture.loader.loadImage(from: imageURL, displayTarget: displayTarget)

        #expect(warmImage === coldImage)
        #expect(await fixture.httpClient.recordedRequests().count == 1)
    }

    @Test
    func relaunchLoadRestoresImageFromCustomDiskCacheWithoutNetworkRequest() async throws {
        let imageURL = try #require(URL(string: "https://example.com/images/relaunch.png"))
        let imageData = makePNGData(width: 80, height: 40)
        let fixture = try makeFixture(
            steps: [
                .dataResponse(
                    statusCode: 200,
                    headers: ["Content-Type": "image/png"],
                    body: imageData
                )
            ]
        )
        defer { fixture.removeTemporaryDirectory() }
        let displayTarget = ArticleImageDisplayTarget(maximumPixelWidth: 40)
        _ = try await fixture.loader.loadImage(from: imageURL, displayTarget: displayTarget)

        let restoredHTTPClient = ScriptedHTTPClient()
        let restoredMemoryCache = ArticleImageMemoryCache(
            countLimit: 8,
            totalCostLimit: 4 * 1024 * 1024
        )
        let restoredDiskCache = ArticleImageDiskCache(
            directoryURL: fixture.directoryURL,
            capacityLimit: 4 * 1024 * 1024
        )
        let restoredLoader = ArticleImageLoader(
            httpClient: restoredHTTPClient,
            memoryCache: restoredMemoryCache,
            diskCache: restoredDiskCache
        )

        let restoredImage = try await restoredLoader.loadImage(
            from: imageURL,
            displayTarget: displayTarget
        )

        #expect(restoredMemoryCache.image(for: imageURL) === restoredImage)
        #expect(await restoredHTTPClient.recordedRequests().isEmpty)
        #expect(try await restoredDiskCache.data(for: imageURL) == imageData)
    }

    @Test
    func repeatedUniqueURLLoadsKeepMemoryBookkeepingWithinCacheCountLimit() async throws {
        let loadCount = 32
        let imageData = makePNGData(width: 32, height: 16)
        let steps = (0..<loadCount).map { _ in
            ScriptedHTTPClient.Step.dataResponse(
                statusCode: 200,
                headers: ["Content-Type": "image/png"],
                body: imageData
            )
        }
        let fixture = try makeFixture(steps: steps, memoryCountLimit: 3)
        defer { fixture.removeTemporaryDirectory() }

        for index in 0..<loadCount {
            let imageURL = try #require(
                URL(string: "https://example.com/images/unique-\(index).png")
            )
            _ = try await fixture.loader.loadImage(
                from: imageURL,
                displayTarget: ArticleImageDisplayTarget(maximumPixelWidth: 16)
            )
        }

        #expect(fixture.memoryCache.cachedImageCount <= 3)
        #expect(fixture.memoryCache.hasImages)
        #expect(await fixture.httpClient.recordedRequests().count == loadCount)
    }

    @Test
    func compressedSmallDecodedHugeImageIsRejectedBeforeDecodeAndBypassesCaches() async throws {
        let imageURL = try #require(URL(string: "https://example.com/images/pixel-bomb.png"))
        let imageData = makePNGData(width: 16, height: 16)
        let budget = makeBudget(
            maximumBodyBytes: Int64(imageData.count + 1),
            maximumPixelWidth: 8,
            maximumPixelHeight: 8,
            maximumPixelCount: 64
        )
        let fixture = try makeFixture(
            steps: [
                .dataResponse(
                    statusCode: 200,
                    headers: ["Content-Type": "image/png"],
                    body: imageData
                )
            ],
            budget: budget
        )
        defer { fixture.removeTemporaryDirectory() }

        await #expect(
            throws: ArticleImageLoadingError.resourceLimitExceeded(
                .imagePixelDimensionsExceeded(
                    input: .articleImage,
                    maximumWidth: 8,
                    maximumHeight: 8,
                    maximumPixelCount: 64,
                    actualWidth: 16,
                    actualHeight: 16
                )
            )
        ) {
            try await fixture.loader.loadImage(
                from: imageURL,
                displayTarget: ArticleImageDisplayTarget(maximumPixelWidth: 8)
            )
        }

        #expect(fixture.memoryCache.image(for: imageURL) == nil)
        #expect(try await fixture.diskCache.data(for: imageURL) == nil)
    }

    @Test
    func invalidMIMEIsRejectedBeforeImageDecodeAndBypassesCaches() async throws {
        let imageURL = try #require(URL(string: "https://example.com/images/wrong-mime.png"))
        let imageData = makePNGData(width: 16, height: 16)
        let fixture = try makeFixture(
            steps: [
                .dataResponse(
                    statusCode: 200,
                    headers: ["Content-Type": "text/html; charset=utf-8"],
                    body: imageData
                )
            ]
        )
        defer { fixture.removeTemporaryDirectory() }

        await #expect(
            throws: ArticleImageLoadingError.resourceLimitExceeded(
                .unsupportedMIMEType(
                    input: .articleImage,
                    receivedMIMEType: "text/html"
                )
            )
        ) {
            try await fixture.loader.loadImage(
                from: imageURL,
                displayTarget: ArticleImageDisplayTarget(maximumPixelWidth: 32)
            )
        }

        #expect(fixture.memoryCache.image(for: imageURL) == nil)
        #expect(try await fixture.diskCache.data(for: imageURL) == nil)
    }

    @Test
    func oversizedTransportPayloadMapsToResourceLimitAndBypassesCaches() async throws {
        let imageURL = try #require(URL(string: "https://example.com/images/oversized.png"))
        let maximumBytes = AppResourceBudgetContract.current.articleImage.body.maximumCompressedBodyBytes
        let fixture = try makeFixture(
            steps: [
                .responseBodyTooLarge(
                    maximumBytes: maximumBytes,
                    actualBytes: maximumBytes + 1
                )
            ]
        )
        defer { fixture.removeTemporaryDirectory() }

        await #expect(
            throws: ArticleImageLoadingError.resourceLimitExceeded(
                .compressedBodySizeExceeded(
                    input: .articleImage,
                    maximumBytes: maximumBytes,
                    actualBytes: maximumBytes + 1
                )
            )
        ) {
            try await fixture.loader.loadImage(
                from: imageURL,
                displayTarget: ArticleImageDisplayTarget(maximumPixelWidth: 320)
            )
        }

        #expect(fixture.memoryCache.image(for: imageURL) == nil)
        #expect(try await fixture.diskCache.data(for: imageURL) == nil)
    }

    @Test
    func cancellationRemainsCancellationAndDoesNotPopulateCaches() async throws {
        let imageURL = try #require(URL(string: "https://example.com/images/slow.png"))
        let fixture = try makeFixture(
            steps: [
                .delayedResponse(
                    statusCode: 200,
                    headers: ["Content-Type": "image/png"],
                    body: "not-reached",
                    delayNanoseconds: 5_000_000_000
                )
            ]
        )
        defer { fixture.removeTemporaryDirectory() }

        let task = Task {
            try await fixture.loader.loadImage(
                from: imageURL,
                displayTarget: ArticleImageDisplayTarget(maximumPixelWidth: 320)
            )
        }

        await Task.yield()
        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(fixture.memoryCache.image(for: imageURL) == nil)
        #expect(try await fixture.diskCache.data(for: imageURL) == nil)
    }

    private func makeFixture(
        steps: [ScriptedHTTPClient.Step],
        budget: RuntimeImageInputBudget = AppResourceBudgetContract.current.articleImage,
        memoryCountLimit: Int = 8
    ) throws -> ArticleImageLoaderFixture {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let httpClient = ScriptedHTTPClient(steps: steps)
        let memoryCache = ArticleImageMemoryCache(
            countLimit: memoryCountLimit,
            totalCostLimit: 4 * 1024 * 1024
        )
        let diskCache = ArticleImageDiskCache(
            directoryURL: directoryURL,
            capacityLimit: 4 * 1024 * 1024
        )
        let loader = ArticleImageLoader(
            httpClient: httpClient,
            memoryCache: memoryCache,
            diskCache: diskCache,
            budget: budget
        )

        return ArticleImageLoaderFixture(
            directoryURL: directoryURL,
            httpClient: httpClient,
            memoryCache: memoryCache,
            diskCache: diskCache,
            loader: loader
        )
    }

    private func makeBudget(
        maximumBodyBytes: Int64,
        maximumPixelWidth: Int,
        maximumPixelHeight: Int,
        maximumPixelCount: Int
    ) -> RuntimeImageInputBudget {
        RuntimeImageInputBudget(
            body: RuntimeInputBodyBudget(
                input: .articleImage,
                maximumCompressedBodyBytes: maximumBodyBytes,
                allowedMIMETypes: ["image/png"]
            ),
            maximumPixelWidth: maximumPixelWidth,
            maximumPixelHeight: maximumPixelHeight,
            maximumPixelCount: maximumPixelCount
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
}

@MainActor
private struct ArticleImageLoaderFixture {
    let directoryURL: URL
    let httpClient: ScriptedHTTPClient
    let memoryCache: ArticleImageMemoryCache
    let diskCache: ArticleImageDiskCache
    let loader: ArticleImageLoader

    func removeTemporaryDirectory() {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}
