import UIKit

@MainActor
final class ArticleImageMemoryCache {
    static let shared = ArticleImageMemoryCache()

    private let storage = NSCache<NSURL, ArticleImageMemoryCacheEntry>()
    private let entryTracker = URLIdentifiedNSCacheTracker<ArticleImageMemoryCacheEntry>()

    init(countLimit: Int = 256, totalCostLimit: Int = 80 * 1024 * 1024) {
        storage.countLimit = countLimit
        storage.totalCostLimit = totalCostLimit
        storage.delegate = entryTracker
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

    func insert(_ image: UIImage, for url: URL) {
        let pixelWidth = image.cgImage?.width ?? max(1, Int(image.size.width.rounded(.up)))
        let pixelHeight = image.cgImage?.height ?? max(1, Int(image.size.height.rounded(.up)))
        insert(
            image,
            for: url,
            sourcePixelWidth: pixelWidth,
            sourcePixelHeight: pixelHeight
        )
    }

    func insert(
        _ image: UIImage,
        for url: URL,
        sourcePixelWidth: Int,
        sourcePixelHeight: Int
    ) {
        let decodedPixelWidth = image.cgImage?.width ?? max(1, Int(image.size.width.rounded(.up)))
        let decodedPixelHeight = image.cgImage?.height ?? max(1, Int(image.size.height.rounded(.up)))
        let decodedByteCost = Self.decodedByteCost(for: image)
        let entry = ArticleImageMemoryCacheEntry(
            cacheURL: url,
            image: image,
            sourcePixelWidth: sourcePixelWidth,
            sourcePixelHeight: sourcePixelHeight,
            decodedMaximumPixelDimension: max(decodedPixelWidth, decodedPixelHeight),
            decodedByteCost: decodedByteCost
        )

        entryTracker.track(entry)
        storage.setObject(
            entry,
            forKey: url as NSURL,
            cost: decodedByteCost
        )
    }

    var hasImages: Bool {
        entryTracker.hasEntries
    }

    var cachedImageCount: Int {
        entryTracker.entryCount
    }

    func cachedDecodedByteCost(for url: URL) -> Int? {
        entry(for: url)?.decodedByteCost
    }

    func removeAllImages() {
        storage.removeAllObjects()
        entryTracker.removeAllEntries()
    }

    private func entry(for url: URL) -> ArticleImageMemoryCacheEntry? {
        guard let entry = storage.object(forKey: url as NSURL) else {
            entryTracker.removeEntry(for: url)
            return nil
        }

        return entry
    }

    static func decodedByteCost(for image: UIImage) -> Int {
        if let cgImage = image.cgImage {
            return saturatedByteCost(bytesPerRow: cgImage.bytesPerRow, height: cgImage.height)
        }

        let scale = image.scale.isFinite && image.scale > 0 ? image.scale : 1
        let pixelWidth = max(1, Int((image.size.width * scale).rounded(.up)))
        let pixelHeight = max(1, Int((image.size.height * scale).rounded(.up)))
        let bytesPerRow = pixelWidth.multipliedReportingOverflow(by: 4)
        guard bytesPerRow.overflow == false else { return Int.max }
        return saturatedByteCost(bytesPerRow: bytesPerRow.partialValue, height: pixelHeight)
    }

    private static func saturatedByteCost(bytesPerRow: Int, height: Int) -> Int {
        let cost = max(1, bytesPerRow).multipliedReportingOverflow(by: max(1, height))
        return cost.overflow ? Int.max : cost.partialValue
    }
}

private final class ArticleImageMemoryCacheEntry: NSObject, URLIdentifiedNSCacheEntry {
    let cacheURL: URL
    let image: UIImage
    let sourcePixelWidth: Int
    let sourcePixelHeight: Int
    let decodedMaximumPixelDimension: Int
    let decodedByteCost: Int

    init(
        cacheURL: URL,
        image: UIImage,
        sourcePixelWidth: Int,
        sourcePixelHeight: Int,
        decodedMaximumPixelDimension: Int,
        decodedByteCost: Int
    ) {
        self.cacheURL = cacheURL
        self.image = image
        self.sourcePixelWidth = sourcePixelWidth
        self.sourcePixelHeight = sourcePixelHeight
        self.decodedMaximumPixelDimension = decodedMaximumPixelDimension
        self.decodedByteCost = decodedByteCost
    }
}
