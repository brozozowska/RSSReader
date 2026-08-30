import Foundation
import Testing
import UIKit
@testable import RSSReader

@Suite("Article Screen / Content Rendering / Image Cache")
@MainActor
struct ArticleScreenImageCacheRenderingTests {
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
