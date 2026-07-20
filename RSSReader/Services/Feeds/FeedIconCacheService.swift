import CryptoKit
import Foundation

public protocol FeedIconCaching: Sendable {
    func cachedImageData(for url: URL) async throws -> Data?
    func storeImageData(_ data: Data, for url: URL) async throws
    func hasCachedData() async throws -> Bool
    func removeAllCachedData() async throws
}

public enum FeedIconCacheError: Error {
    case emptyImageData
}

public actor FeedIconCacheService: FeedIconCaching {
    private let cache: FeedIconMemoryCache
    private let diskCache: FeedIconDiskCache

    public init(
        cache: FeedIconMemoryCache? = nil,
        diskCache: FeedIconDiskCache? = nil
    ) {
        self.cache = cache ?? FeedIconMemoryCache()
        self.diskCache = diskCache ?? FeedIconDiskCache.shared
    }

    public func cachedImageData(for url: URL) async throws -> Data? {
        if let cachedData = await cache.data(for: url) {
            return cachedData
        }

        if let diskCachedData = try await diskCache.data(for: url) {
            await cache.insert(diskCachedData, for: url)
            return diskCachedData
        }

        return nil
    }

    public func storeImageData(_ data: Data, for url: URL) async throws {
        guard data.isEmpty == false else {
            throw FeedIconCacheError.emptyImageData
        }

        try await diskCache.insert(data, for: url)
        await cache.insert(data, for: url)
    }

    public func hasCachedData() async throws -> Bool {
        let hasMemoryCache = await cache.hasCachedData()
        guard hasMemoryCache == false else {
            return true
        }

        return try await diskCache.isEmpty() == false
    }

    public func removeAllCachedData() async throws {
        await cache.removeAll()
        try await diskCache.removeAll()
    }
}

public actor FeedIconMemoryCache {
    private let storage = NSCache<NSURL, FeedIconMemoryCacheEntry>()
    private let entryTracker = URLIdentifiedNSCacheTracker<FeedIconMemoryCacheEntry>()

    public init(countLimit: Int = 256) {
        storage.countLimit = countLimit
        storage.delegate = entryTracker
    }

    func data(for url: URL) -> Data? {
        guard let entry = storage.object(forKey: url as NSURL) else {
            entryTracker.removeEntry(for: url)
            return nil
        }

        return entry.data
    }

    func insert(_ data: Data, for url: URL) {
        let entry = FeedIconMemoryCacheEntry(cacheURL: url, data: data)
        entryTracker.track(entry)
        storage.setObject(entry, forKey: url as NSURL)
    }

    func hasCachedData() -> Bool {
        entryTracker.hasEntries
    }

    func cachedEntryCount() -> Int {
        entryTracker.entryCount
    }

    func removeAll() {
        storage.removeAllObjects()
        entryTracker.removeAllEntries()
    }
}

private final class FeedIconMemoryCacheEntry: NSObject, URLIdentifiedNSCacheEntry {
    let cacheURL: URL
    let data: Data

    init(cacheURL: URL, data: Data) {
        self.cacheURL = cacheURL
        self.data = data
    }
}

public actor FeedIconDiskCache {
    public static let shared = FeedIconDiskCache()
    static let directoryName = "RSSReaderFeedIcons"

    private let directoryURL: URL
    private let capacityLimit: Int64
    private let fileManager: FileManager
    private let dateProvider: @Sendable () -> Date

    init(
        directoryURL: URL? = nil,
        capacityLimit: Int64 = 25 * 1024 * 1024,
        fileManager: FileManager = .default,
        dateProvider: @escaping @Sendable () -> Date = Date.init
    ) {
        self.directoryURL = directoryURL ?? Self.defaultDirectoryURL(fileManager: fileManager)
        self.capacityLimit = capacityLimit
        self.fileManager = fileManager
        self.dateProvider = dateProvider
    }

    func data(for url: URL) throws -> Data? {
        let fileURL = fileURL(for: url)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: fileURL)
        try touch(fileURL)
        return data
    }

    func insert(_ data: Data, for url: URL) throws {
        try prepareDirectoryIfNeeded()

        let fileURL = fileURL(for: url)
        try data.write(to: fileURL, options: .atomic)
        try touch(fileURL)
        try enforceCapacityLimit()
    }

    func removeAll() throws {
        guard fileManager.fileExists(atPath: directoryURL.path) else {
            return
        }

        let fileURLs = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )

        for fileURL in fileURLs {
            try fileManager.removeItem(at: fileURL)
        }
    }

    func isEmpty() throws -> Bool {
        try cacheEntries().isEmpty
    }

    private static func defaultDirectoryURL(fileManager: FileManager) -> URL {
        let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return cachesDirectory.appendingPathComponent(directoryName, isDirectory: true)
    }

    private func prepareDirectoryIfNeeded() throws {
        guard fileManager.fileExists(atPath: directoryURL.path) == false else {
            return
        }

        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
    }

    private func fileURL(for url: URL) -> URL {
        directoryURL.appendingPathComponent(Self.cacheKey(for: url), isDirectory: false)
    }

    private static func cacheKey(for url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let key = digest.map { String(format: "%02x", $0) }.joined()
        return "\(key).feed-icon"
    }

    private func touch(_ fileURL: URL) throws {
        try fileManager.setAttributes(
            [.modificationDate: dateProvider()],
            ofItemAtPath: fileURL.path
        )
    }

    private func enforceCapacityLimit() throws {
        let entries = try cacheEntries()
        var totalSize = entries.reduce(Int64(0)) { $0 + $1.size }

        for entry in entries.sorted(by: { $0.lastAccessedAt < $1.lastAccessedAt }) where totalSize > capacityLimit {
            try fileManager.removeItem(at: entry.fileURL)
            totalSize -= entry.size
        }
    }

    private func cacheEntries() throws -> [FeedIconDiskCacheEntry] {
        guard fileManager.fileExists(atPath: directoryURL.path) else {
            return []
        }

        let resourceKeys: Set<URLResourceKey> = [
            .contentModificationDateKey,
            .fileSizeKey,
            .isRegularFileKey
        ]
        let fileURLs = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: Array(resourceKeys)
        )

        return try fileURLs.compactMap { fileURL in
            let resourceValues = try fileURL.resourceValues(forKeys: resourceKeys)
            guard resourceValues.isRegularFile == true else { return nil }

            return FeedIconDiskCacheEntry(
                fileURL: fileURL,
                size: Int64(resourceValues.fileSize ?? 0),
                lastAccessedAt: resourceValues.contentModificationDate ?? .distantPast
            )
        }
    }
}

private struct FeedIconDiskCacheEntry {
    let fileURL: URL
    let size: Int64
    let lastAccessedAt: Date
}
