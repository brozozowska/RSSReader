import UIKit

@MainActor
final class ArticleImageMemoryCache {
    static let shared = ArticleImageMemoryCache()

    private let storage = NSCache<NSURL, ArticleImageMemoryCacheEntry>()
    private let entryTracker = URLIdentifiedNSCacheTracker<ArticleImageMemoryCacheEntry>()
    private let totalCountLimit: Int
    private let totalCostLimit: Int
    private let prefetchReservationCountLimit: Int
    private var desiredPrefetchURLs: [URL] = []
    private var prefetchedEntries: [URL: ArticleImageMemoryCacheEntry] = [:]
    private var prefetchedDecodedByteCost = 0

    init(countLimit: Int = 256, totalCostLimit: Int = 80 * 1024 * 1024) {
        precondition(countLimit > 0)
        precondition(totalCostLimit > 0)

        let reservationCountLimit = min(
            ReaderAdjacentArticleImagePrefetchPolicy.maximumReservedImageCount,
            max(0, countLimit - 1)
        )
        self.totalCountLimit = countLimit
        self.totalCostLimit = totalCostLimit
        self.prefetchReservationCountLimit = reservationCountLimit
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

        // ImageIO may round a JPEG thumbnail down by a pixel. A completed decode
        // still satisfies its requested target; do not repeatedly decode it.
        guard targetMaximumPixelWidth <= entry.preparedMaximumPixelWidth
                || entry.decodedMaximumPixelDimension >= requiredMaximumPixelDimension else {
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
        sourcePixelHeight: Int,
        preparedForMaximumPixelWidth: Int? = nil
    ) {
        let decodedPixelWidth = image.cgImage?.width ?? max(1, Int(image.size.width.rounded(.up)))
        let decodedPixelHeight = image.cgImage?.height ?? max(1, Int(image.size.height.rounded(.up)))
        let decodedByteCost = Self.decodedByteCost(for: image)
        var preparedMaximumPixelWidth = preparedForMaximumPixelWidth ?? 0
        if let existingEntry = entry(for: url),
           existingEntry.sourcePixelWidth == sourcePixelWidth,
           existingEntry.sourcePixelHeight == sourcePixelHeight {
            preparedMaximumPixelWidth = max(preparedMaximumPixelWidth, existingEntry.preparedMaximumPixelWidth)
            if existingEntry.decodedMaximumPixelDimension >= max(decodedPixelWidth, decodedPixelHeight) {
                // Different target sizes may finish out of order. Keep the best
                // decoded representation and merge completed target coverage.
                existingEntry.preparedMaximumPixelWidth = preparedMaximumPixelWidth
                return
            }
        }
        let entry = ArticleImageMemoryCacheEntry(
            cacheURL: url,
            image: image,
            sourcePixelWidth: sourcePixelWidth,
            sourcePixelHeight: sourcePixelHeight,
            decodedMaximumPixelDimension: max(decodedPixelWidth, decodedPixelHeight),
            decodedByteCost: decodedByteCost,
            preparedMaximumPixelWidth: preparedMaximumPixelWidth
        )

        if desiredPrefetchURLs.contains(url) {
            // Promote directly: the ordinary cache's residual budget may be
            // smaller than an upgrade that fits after replacing its reservation.
            reconcilePrefetchReservations(inserting: entry)
        } else {
            insertOrdinaryEntry(entry)
        }
    }

    func replacePrefetchReservations(with urls: [URL]) {
        var seenURLs = Set<URL>()
        desiredPrefetchURLs = urls
            .filter { seenURLs.insert($0).inserted }
            .prefix(prefetchReservationCountLimit)
            .map { $0 }
        reconcilePrefetchReservations()
    }

    func clearPrefetchReservations() {
        desiredPrefetchURLs = []
        reconcilePrefetchReservations()
    }

    var hasImages: Bool {
        prefetchedEntries.isEmpty == false || entryTracker.hasEntries
    }

    var cachedImageCount: Int {
        prefetchedEntries.count + entryTracker.entryCount
    }

    func cachedDecodedByteCost(for url: URL) -> Int? {
        entry(for: url)?.decodedByteCost
    }

    func removeAllImages() {
        desiredPrefetchURLs = []
        prefetchedEntries.removeAll()
        prefetchedDecodedByteCost = 0
        storage.removeAllObjects()
        entryTracker.removeAllEntries()
    }

    private func entry(for url: URL) -> ArticleImageMemoryCacheEntry? {
        if let prefetchedEntry = prefetchedEntries[url] {
            return prefetchedEntry
        }

        guard let entry = storage.object(forKey: url as NSURL) else {
            entryTracker.removeEntry(for: url)
            return nil
        }

        return entry
    }

    private func insertOrdinaryEntry(_ entry: ArticleImageMemoryCacheEntry) {
        entryTracker.track(entry)
        storage.setObject(
            entry,
            forKey: entry.cacheURL as NSURL,
            cost: entry.decodedByteCost
        )
    }

    private func reconcilePrefetchReservations(inserting insertedEntry: ArticleImageMemoryCacheEntry? = nil) {
        let previousPrefetchedEntries = prefetchedEntries
        var candidatesByURL = previousPrefetchedEntries
        for url in desiredPrefetchURLs {
            if let entry = storage.object(forKey: url as NSURL) {
                candidatesByURL[url] = entry
            }
        }
        if let insertedEntry {
            candidatesByURL[insertedEntry.cacheURL] = insertedEntry
        }

        var nextPrefetchedEntries: [URL: ArticleImageMemoryCacheEntry] = [:]
        var nextPrefetchedDecodedByteCost = 0
        for url in desiredPrefetchURLs {
            guard let entry = candidatesByURL[url] else { continue }
            let nextCost = nextPrefetchedDecodedByteCost.addingReportingOverflow(entry.decodedByteCost)
            guard nextCost.overflow == false,
                  nextCost.partialValue <= totalCostLimit else {
                continue
            }

            nextPrefetchedEntries[url] = entry
            nextPrefetchedDecodedByteCost = nextCost.partialValue
        }

        prefetchedEntries = nextPrefetchedEntries
        prefetchedDecodedByteCost = nextPrefetchedDecodedByteCost
        storage.countLimit = max(1, totalCountLimit - nextPrefetchedEntries.count)
        storage.totalCostLimit = max(1, totalCostLimit - nextPrefetchedDecodedByteCost)

        for (url, entry) in previousPrefetchedEntries where nextPrefetchedEntries[url] == nil {
            insertOrdinaryEntry(entry)
        }
        for url in nextPrefetchedEntries.keys {
            storage.removeObject(forKey: url as NSURL)
            entryTracker.removeEntry(for: url)
        }
        if let insertedEntry, nextPrefetchedEntries[insertedEntry.cacheURL] == nil {
            insertOrdinaryEntry(insertedEntry)
        }
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
    var preparedMaximumPixelWidth: Int

    init(
        cacheURL: URL,
        image: UIImage,
        sourcePixelWidth: Int,
        sourcePixelHeight: Int,
        decodedMaximumPixelDimension: Int,
        decodedByteCost: Int,
        preparedMaximumPixelWidth: Int
    ) {
        self.cacheURL = cacheURL
        self.image = image
        self.sourcePixelWidth = sourcePixelWidth
        self.sourcePixelHeight = sourcePixelHeight
        self.decodedMaximumPixelDimension = decodedMaximumPixelDimension
        self.decodedByteCost = decodedByteCost
        self.preparedMaximumPixelWidth = preparedMaximumPixelWidth
    }
}
