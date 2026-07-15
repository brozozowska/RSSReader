import UIKit

@MainActor
final class ArticleImageMemoryCache {
    static let shared = ArticleImageMemoryCache()

    private let storage = NSCache<NSURL, ArticleImageMemoryCacheEntry>()
    private var storedURLs: Set<URL> = []

    init(countLimit: Int = 256, totalCostLimit: Int = 80 * 1024 * 1024) {
        storage.countLimit = countLimit
        storage.totalCostLimit = totalCostLimit
    }

    func image(for url: URL) -> UIImage? {
        entry(for: url)?.image
    }

    func image(for url: URL, targetMaximumPixelWidth: Int) -> UIImage? {
        guard let entry = entry(for: url) else { return nil }

        let requiredMaximumPixelDimension = ArticleImageDownsamplingPolicy.maximumPixelDimension(
            sourceWidth: entry.sourcePixelWidth,
            sourceHeight: entry.sourcePixelHeight,
            targetMaximumPixelWidth: targetMaximumPixelWidth
        )

        guard entry.decodedMaximumPixelDimension >= requiredMaximumPixelDimension else {
            return nil
        }

        return entry.image
    }

    func insert(_ image: UIImage, for url: URL, cost: Int = 0) {
        let pixelWidth = image.cgImage?.width ?? max(1, Int(image.size.width.rounded(.up)))
        let pixelHeight = image.cgImage?.height ?? max(1, Int(image.size.height.rounded(.up)))
        insert(
            image,
            for: url,
            sourcePixelWidth: pixelWidth,
            sourcePixelHeight: pixelHeight,
            cost: cost
        )
    }

    func insert(
        _ image: UIImage,
        for url: URL,
        sourcePixelWidth: Int,
        sourcePixelHeight: Int,
        cost: Int
    ) {
        let decodedPixelWidth = image.cgImage?.width ?? max(1, Int(image.size.width.rounded(.up)))
        let decodedPixelHeight = image.cgImage?.height ?? max(1, Int(image.size.height.rounded(.up)))
        let entry = ArticleImageMemoryCacheEntry(
            image: image,
            sourcePixelWidth: sourcePixelWidth,
            sourcePixelHeight: sourcePixelHeight,
            decodedMaximumPixelDimension: max(decodedPixelWidth, decodedPixelHeight)
        )

        storage.setObject(entry, forKey: url as NSURL, cost: cost)
        storedURLs.insert(url)
    }

    var hasImages: Bool {
        for url in Array(storedURLs) where image(for: url) != nil {
            return true
        }

        return false
    }

    func removeAllImages() {
        storage.removeAllObjects()
        storedURLs.removeAll()
    }

    private func entry(for url: URL) -> ArticleImageMemoryCacheEntry? {
        guard let entry = storage.object(forKey: url as NSURL) else {
            storedURLs.remove(url)
            return nil
        }

        return entry
    }
}

private final class ArticleImageMemoryCacheEntry: NSObject {
    let image: UIImage
    let sourcePixelWidth: Int
    let sourcePixelHeight: Int
    let decodedMaximumPixelDimension: Int

    init(
        image: UIImage,
        sourcePixelWidth: Int,
        sourcePixelHeight: Int,
        decodedMaximumPixelDimension: Int
    ) {
        self.image = image
        self.sourcePixelWidth = sourcePixelWidth
        self.sourcePixelHeight = sourcePixelHeight
        self.decodedMaximumPixelDimension = decodedMaximumPixelDimension
    }
}
