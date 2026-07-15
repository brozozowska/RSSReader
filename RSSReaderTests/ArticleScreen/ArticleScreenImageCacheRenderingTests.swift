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

        cache.insert(image, for: imageURL, cost: 16)
        let cachedImage = try #require(cache.image(for: imageURL))

        #expect(cachedImage === image)
        #expect(cache.image(for: otherURL) == nil)
    }

    @Test
    func articleImageMemoryCacheCanBeCleared() {
        let cache = ArticleImageMemoryCache(countLimit: 2, totalCostLimit: 1_024)
        let imageURL = URL(string: "https://example.com/article-image.png")!

        cache.insert(makeTestImage(), for: imageURL, cost: 16)
        cache.removeAllImages()

        #expect(cache.image(for: imageURL) == nil)
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
            sourcePixelHeight: 60,
            cost: 24 * 12 * 4
        )

        #expect(cache.image(for: imageURL, targetMaximumPixelWidth: 24) === image)
        #expect(cache.image(for: imageURL, targetMaximumPixelWidth: 60) == nil)
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

    private func makeSizedTestImage(size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}
