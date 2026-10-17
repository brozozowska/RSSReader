import Foundation
import Testing
import UIKit
@testable import RSSReader

@Suite("Article Screen / Content Rendering / Image Cache")
@MainActor
struct ArticleScreenImageCacheRenderingTests {
    @Test
    func reservedUpgradeUsesReplacementBudgetBeforeOrdinaryEviction() throws {
        let small = makeSizedTestImage(size: CGSize(width: 16, height: 8))
        let large = makeSizedTestImage(size: CGSize(width: 32, height: 16))
        let smallCost = ArticleImageMemoryCache.decodedByteCost(for: small)
        let largeCost = ArticleImageMemoryCache.decodedByteCost(for: large)
        let budget = smallCost * 4 + largeCost
        let cache = ArticleImageMemoryCache(countLimit: 6, totalCostLimit: budget)
        let urls = (0..<5).map { URL(string: "https://example.com/reservation-\($0).png")! }
        cache.replacePrefetchReservations(with: urls)
        for url in urls {
            cache.insert(small, for: url, sourcePixelWidth: 64, sourcePixelHeight: 32)
        }
        cache.insert(large, for: urls[2], sourcePixelWidth: 64, sourcePixelHeight: 32)

        #expect(cache.image(for: urls[2], targetMaximumPixelWidth: 32) === large)
        #expect(urls.compactMap { cache.cachedDecodedByteCost(for: $0) }.reduce(0, +) == budget)
        for index in 0..<10 {
            cache.insert(small, for: URL(string: "https://example.com/churn-upgrade-\(index).png")!)
        }
        #expect(cache.image(for: urls[2]) === large)
        #expect(urls.allSatisfy { cache.image(for: $0) != nil })
        #expect(cache.cachedImageCount == 5)
        cache.removeAllImages()
        #expect(cache.cachedImageCount == 0)
        #expect(cache.hasImages == false)
    }

    @Test
    func reservedImagesOverBudgetDoNotBypassMemoryLimit() {
        let image = makeSizedTestImage(size: CGSize(width: 16, height: 8))
        let cost = ArticleImageMemoryCache.decodedByteCost(for: image)
        let cache = ArticleImageMemoryCache(countLimit: 4, totalCostLimit: cost * 2)
        let urls = (0..<3).map { URL(string: "https://example.com/budget-\($0).png")! }
        cache.replacePrefetchReservations(with: urls)
        for url in urls { cache.insert(image, for: url) }
        #expect(urls.compactMap { cache.cachedDecodedByteCost(for: $0) }.reduce(0, +) <= cost * 2)
        #expect(cache.cachedImageCount <= 2)
    }

    @Test
    func changedSourceDimensionsDoNotInheritCompletedTargetCoverage() {
        let cache = ArticleImageMemoryCache()
        let url = URL(string: "https://example.com/replaced-source.png")!
        cache.insert(makeSizedTestImage(size: CGSize(width: 24, height: 12)), for: url,
                     sourcePixelWidth: 48, sourcePixelHeight: 24, preparedForMaximumPixelWidth: 24)
        let replacement = makeSizedTestImage(size: CGSize(width: 8, height: 8))
        cache.insert(replacement, for: url, sourcePixelWidth: 80, sourcePixelHeight: 80,
                     preparedForMaximumPixelWidth: 8)
        #expect(cache.image(for: url) === replacement)
        #expect(cache.image(for: url, targetMaximumPixelWidth: 24) == nil)
    }

    @Test
    func largerTargetKeepsVisibleImageThroughFailureCancellationAndRetry() throws {
        let url = URL(string: "https://example.com/upgrade.png")!
        let image = makeTestImage()
        var lifecycle = CachedArticleImageLoadLifecycle(initialPhase: .success(image), imageURL: url)
        let request = CachedArticleImageLoadRequest(url: url, displayTarget: .init(maximumPixelWidth: 640))
        let pendingToken = lifecycle.beginLoadingIfNeeded(request, cachedImage: nil)
        let failed = try #require(pendingToken)
        #expect(lifecycle.phase.successfulImage === image)
        lifecycle.fail(failed)
        #expect(lifecycle.phase.successfulImage === image)
        let cancelled = lifecycle.begin(request)
        lifecycle.cancel(cancelled)
        #expect(lifecycle.phase.successfulImage === image)
        let retry = lifecycle.begin(request)
        lifecycle.fail(failed)
        lifecycle.cancel(cancelled)
        #expect(lifecycle.phase.successfulImage === image)
        let upgraded = makeSizedTestImage(size: CGSize(width: 32, height: 16))
        lifecycle.succeed(with: upgraded, token: retry)
        #expect(lifecycle.phase.successfulImage === upgraded)
    }

    @Test
    func URLChangeDoesNotKeepPreviousSuccessfulImageOrAcceptStaleUpgrade() {
        let firstURL = URL(string: "https://example.com/first.png")!
        let secondURL = URL(string: "https://example.com/second.png")!
        let image = makeTestImage()
        var lifecycle = CachedArticleImageLoadLifecycle(initialPhase: .success(image), imageURL: firstURL)
        let stale = lifecycle.begin(.init(url: firstURL, displayTarget: .init(maximumPixelWidth: 640)))
        let current = lifecycle.begin(.init(url: secondURL, displayTarget: .init(maximumPixelWidth: 640)))
        #expect(lifecycle.phase.isLoading)
        lifecycle.succeed(with: image, token: stale)
        lifecycle.cancel(stale)
        #expect(lifecycle.phase.isLoading)
        lifecycle.fail(current)
        #expect(lifecycle.phase.isFailure)
    }

    @Test
    func articleImageMemoryCacheStoresDecodedImagesByURL() throws {
        let cache = ArticleImageMemoryCache(countLimit: 2, totalCostLimit: 1_024)
        let imageURL = URL(string: "https://example.com/article-image.png")!
        let otherURL = URL(string: "https://example.com/other-image.png")!
        let image = makeTestImage()

        cache.insert(image, for: imageURL)
        let cachedImage = try #require(cache.image(for: imageURL))

        #expect(cachedImage === image)
        #expect(cache.image(for: otherURL) == nil)
        #expect(cache.hasImages)
        #expect(cache.cachedImageCount == 1)
    }

    @Test
    func articleImageMemoryCacheCanBeCleared() {
        let cache = ArticleImageMemoryCache(countLimit: 2, totalCostLimit: 1_024)
        let imageURL = URL(string: "https://example.com/article-image.png")!

        cache.insert(makeTestImage(), for: imageURL)
        cache.removeAllImages()

        #expect(cache.image(for: imageURL) == nil)
        #expect(cache.hasImages == false)
        #expect(cache.cachedImageCount == 0)
    }

    @Test
    func articleImageMemoryCacheRequiresEnoughDecodedPixelsForDisplayTarget() throws {
        let cache = ArticleImageMemoryCache(countLimit: 2, totalCostLimit: 4_096)
        let imageURL = URL(string: "https://example.com/article-image.png")!
        let image = makeSizedTestImage(size: CGSize(width: 24, height: 12))

        cache.insert(
            image,
            for: imageURL,
            sourcePixelWidth: 120,
            sourcePixelHeight: 60
        )

        #expect(cache.image(for: imageURL, targetMaximumPixelWidth: 24) === image)
        #expect(cache.image(for: imageURL, targetMaximumPixelWidth: 60) == nil)
    }

    @Test
    func articleImageMemoryCacheUsesDecodedBitmapFootprintAsCost() throws {
        let cache = ArticleImageMemoryCache(countLimit: 2, totalCostLimit: 4_096)
        let imageURL = try #require(URL(string: "https://example.com/decoded-cost.png"))
        let image = makeSizedTestImage(size: CGSize(width: 24, height: 12))
        let cgImage = try #require(image.cgImage)

        cache.insert(image, for: imageURL)

        #expect(
            cache.cachedDecodedByteCost(for: imageURL)
                == cgImage.bytesPerRow * cgImage.height
        )
    }

    @Test
    func articleImageMemoryCacheSynchronizesAutomaticEvictionWithAvailability() throws {
        let cache = ArticleImageMemoryCache(countLimit: 1, totalCostLimit: 4_096)
        let firstURL = try #require(URL(string: "https://example.com/first.png"))
        let secondURL = try #require(URL(string: "https://example.com/second.png"))

        cache.insert(makeTestImage(), for: firstURL)
        cache.insert(makeTestImage(), for: secondURL)

        let cachedImages = [firstURL, secondURL].compactMap { cache.image(for: $0) }
        #expect(cachedImages.count == 1)
        #expect(cache.cachedImageCount == 1)
        #expect(cache.hasImages)
    }

    @Test
    func adjacentPrefetchReservationsSurviveOrdinaryCacheChurn() throws {
        let cache = ArticleImageMemoryCache(countLimit: 3, totalCostLimit: 16_384)
        let previousURL = try #require(URL(string: "https://example.com/previous.png"))
        let nextURL = try #require(URL(string: "https://example.com/next.png"))
        cache.replacePrefetchReservations(with: [previousURL, nextURL])

        let previousImage = makeSizedTestImage(size: CGSize(width: 16, height: 8))
        let nextImage = makeSizedTestImage(size: CGSize(width: 16, height: 8))
        cache.insert(previousImage, for: previousURL)
        cache.insert(nextImage, for: nextURL)

        for index in 0..<20 {
            let churnURL = try #require(URL(string: "https://example.com/churn-\(index).png"))
            cache.insert(makeSizedTestImage(size: CGSize(width: 16, height: 8)), for: churnURL)
        }

        #expect(cache.image(for: previousURL) === previousImage)
        #expect(cache.image(for: nextURL) === nextImage)
        #expect(cache.cachedImageCount <= 3)
    }

    @Test
    func replacingAdjacentReservationsReleasesOldWindowAndProtectsNewWindow() throws {
        let cache = ArticleImageMemoryCache(countLimit: 3, totalCostLimit: 16_384)
        let oldURL = try #require(URL(string: "https://example.com/old.png"))
        let newURL = try #require(URL(string: "https://example.com/new.png"))
        cache.replacePrefetchReservations(with: [oldURL])
        cache.insert(makeSizedTestImage(size: CGSize(width: 16, height: 8)), for: oldURL)

        cache.replacePrefetchReservations(with: [newURL])
        let newImage = makeSizedTestImage(size: CGSize(width: 16, height: 8))
        cache.insert(newImage, for: newURL)
        for index in 0..<4 {
            let churnURL = try #require(URL(string: "https://example.com/replacement-\(index).png"))
            cache.insert(makeSizedTestImage(size: CGSize(width: 16, height: 8)), for: churnURL)
        }

        #expect(cache.image(for: newURL) === newImage)
        #expect(cache.image(for: oldURL) == nil)
        #expect(cache.cachedImageCount <= 3)
    }

    @Test
    func currentAndFourAdjacentImageReservationsSurviveOrdinaryCacheChurnWithinOriginalBudget() throws {
        let cache = ArticleImageMemoryCache(countLimit: 6, totalCostLimit: 32_768)
        let reservedURLs = try (0..<5).map { index in
            try #require(URL(string: "https://example.com/reserved-\(index).png"))
        }
        cache.replacePrefetchReservations(with: reservedURLs)
        let reservedImages = reservedURLs.map { url in
            let image = makeSizedTestImage(size: CGSize(width: 16, height: 8))
            cache.insert(image, for: url)
            return image
        }

        for index in 0..<8 {
            let churnURL = try #require(URL(string: "https://example.com/four-window-churn-\(index).png"))
            cache.insert(makeSizedTestImage(size: CGSize(width: 16, height: 8)), for: churnURL)
        }

        for (index, url) in reservedURLs.enumerated() {
            #expect(cache.image(for: url) === reservedImages[index])
        }
        #expect(cache.cachedImageCount <= 6)
    }

    @Test
    func reservedURLUsesNewestSufficientDecodedEntry() throws {
        let cache = ArticleImageMemoryCache(countLimit: 3, totalCostLimit: 32_768)
        let imageURL = try #require(URL(string: "https://example.com/resized.png"))
        cache.replacePrefetchReservations(with: [imageURL])
        cache.insert(
            makeSizedTestImage(size: CGSize(width: 16, height: 8)),
            for: imageURL,
            sourcePixelWidth: 64,
            sourcePixelHeight: 32
        )

        let largerImage = makeSizedTestImage(size: CGSize(width: 48, height: 24))
        cache.insert(
            largerImage,
            for: imageURL,
            sourcePixelWidth: 64,
            sourcePixelHeight: 32
        )

        #expect(cache.image(for: imageURL, targetMaximumPixelWidth: 48) === largerImage)
    }

    @Test
    func cachedArticleImageLayoutPolicyDoesNotUpscaleSmallImages() {
        let layout = CachedArticleImageLayoutPolicy.layout(for: CGSize(width: 120, height: 80))

        #expect(layout.maxImageWidth == 120)
        #expect(layout.horizontalAlignment == .center)
    }

    @Test
    func cachedArticleImageLayoutPolicyKeepsLargeImagesAdaptive() {
        let layout = CachedArticleImageLayoutPolicy.layout(for: CGSize(width: 1_200, height: 800))

        #expect(layout.maxImageWidth == nil)
        #expect(layout.horizontalAlignment == .center)
    }

    @Test
    func cancelledCurrentLoadReturnsToRetryableEmptyPhase() throws {
        let request = CachedArticleImageLoadRequest(
            url: try #require(URL(string: "https://example.com/cancelled.png")),
            displayTarget: ArticleImageDisplayTarget(maximumPixelWidth: 320)
        )
        var lifecycle = CachedArticleImageLoadLifecycle(initialPhase: .empty)

        let cancelledToken = lifecycle.begin(request)
        lifecycle.cancel(cancelledToken)
        #expect(lifecycle.phase.isEmpty)

        _ = lifecycle.begin(request)
        #expect(lifecycle.phase.isLoading)
    }

    @Test
    func displayTargetChangeIgnoresStaleCompletion() throws {
        let imageURL = try #require(URL(string: "https://example.com/responsive.png"))
        let narrowRequest = CachedArticleImageLoadRequest(
            url: imageURL,
            displayTarget: ArticleImageDisplayTarget(maximumPixelWidth: 320)
        )
        let wideRequest = CachedArticleImageLoadRequest(
            url: imageURL,
            displayTarget: ArticleImageDisplayTarget(maximumPixelWidth: 640)
        )
        let staleImage = makeTestImage()
        let currentImage = makeSizedTestImage(size: CGSize(width: 2, height: 2))
        var lifecycle = CachedArticleImageLoadLifecycle(initialPhase: .empty)

        let staleToken = lifecycle.begin(narrowRequest)
        let currentToken = lifecycle.begin(wideRequest)
        lifecycle.succeed(with: staleImage, token: staleToken)
        #expect(lifecycle.phase.isLoading)

        lifecycle.succeed(with: currentImage, token: currentToken)
        #expect(lifecycle.phase.successfulImage === currentImage)
    }

    @Test
    func URLChangeAndRetryCannotBeOverwrittenByStaleTask() throws {
        let firstRequest = CachedArticleImageLoadRequest(
            url: try #require(URL(string: "https://example.com/first.png")),
            displayTarget: ArticleImageDisplayTarget(maximumPixelWidth: 320)
        )
        let secondRequest = CachedArticleImageLoadRequest(
            url: try #require(URL(string: "https://example.com/second.png")),
            displayTarget: ArticleImageDisplayTarget(maximumPixelWidth: 320)
        )
        var lifecycle = CachedArticleImageLoadLifecycle(initialPhase: .empty)

        let staleToken = lifecycle.begin(firstRequest)
        let failedToken = lifecycle.begin(secondRequest)
        lifecycle.fail(failedToken)
        #expect(lifecycle.phase.isFailure)

        let retryToken = lifecycle.begin(secondRequest)
        lifecycle.cancel(staleToken)
        #expect(lifecycle.phase.isLoading)

        let retryImage = makeTestImage()
        lifecycle.succeed(with: retryImage, token: retryToken)
        #expect(lifecycle.phase.successfulImage === retryImage)
    }

    @Test
    func memoryCacheHitStartsInSuccessPhase() {
        let image = makeTestImage()
        let lifecycle = CachedArticleImageLoadLifecycle(initialPhase: .success(image))

        #expect(lifecycle.phase.successfulImage === image)
    }

    @Test
    func geometryTriggeredTaskKeepsSufficientMemoryCacheHitVisible() throws {
        let request = CachedArticleImageLoadRequest(
            url: try #require(URL(string: "https://example.com/prefetched.png")),
            displayTarget: ArticleImageDisplayTarget(maximumPixelWidth: 640)
        )
        let prefetchedImage = makeSizedTestImage(size: CGSize(width: 640, height: 320))
        var lifecycle = CachedArticleImageLoadLifecycle(initialPhase: .empty)

        let token = lifecycle.beginLoadingIfNeeded(request, cachedImage: prefetchedImage)

        #expect(token == nil)
        #expect(lifecycle.phase.successfulImage === prefetchedImage)
        #expect(lifecycle.phase.isLoading == false)
    }

    private func makeSizedTestImage(size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}

private extension CachedArticleImagePhase {
    var isEmpty: Bool {
        if case .empty = self { return true }
        return false
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var isFailure: Bool {
        if case .failure = self { return true }
        return false
    }

    var successfulImage: UIImage? {
        if case .success(let image) = self { return image }
        return nil
    }
}
