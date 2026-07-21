import Foundation
import Testing
@testable import RSSReader

@Suite("Article Screen / Article Image Disk Cache")
struct ArticleImageDiskCacheTests {
    @Test
    func articleImageDiskCachePersistsBytesByURL() async throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let imageURL = URL(string: "https://example.com/images/article.png")!
        let data = Data([1, 2, 3, 4])
        let cache = ArticleImageDiskCache(directoryURL: directoryURL, capacityLimit: 1_024)

        try await cache.insert(data, for: imageURL)

        let restoredCache = ArticleImageDiskCache(directoryURL: directoryURL, capacityLimit: 1_024)
        let restoredData = try await restoredCache.data(for: imageURL)
        #expect(restoredData == data)
    }

    @Test
    func articleImageDiskCacheDoesNotRetainSingleEntryLargerThanCapacity() async throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let imageURL = URL(string: "https://example.com/images/oversized-cache-entry.png")!
        let cache = ArticleImageDiskCache(directoryURL: directoryURL, capacityLimit: 4)

        try await cache.insert(Data(repeating: 1, count: 5), for: imageURL)

        #expect(try await cache.data(for: imageURL) == nil)
        #expect(try await cache.isEmpty())
    }

    @Test
    func articleImageDiskCacheEvictsLeastRecentlyUsedBytesWhenCapacityIsExceeded() async throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let dateProvider = IncrementingDateProvider()
        let firstURL = URL(string: "https://example.com/images/first.png")!
        let secondURL = URL(string: "https://example.com/images/second.png")!
        let firstData = Data([1, 1, 1, 1])
        let secondData = Data([2, 2, 2, 2])
        let cache = ArticleImageDiskCache(
            directoryURL: directoryURL,
            capacityLimit: 4,
            dateProvider: { dateProvider.next() }
        )

        try await cache.insert(firstData, for: firstURL)
        try await cache.insert(secondData, for: secondURL)

        let evictedData = try await cache.data(for: firstURL)
        let retainedData = try await cache.data(for: secondURL)
        #expect(evictedData == nil)
        #expect(retainedData == secondData)
    }

    @Test
    func articleImageDiskCacheUpdatesAccessOrderOnRead() async throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let dateProvider = IncrementingDateProvider()
        let firstURL = URL(string: "https://example.com/images/first.png")!
        let secondURL = URL(string: "https://example.com/images/second.png")!
        let thirdURL = URL(string: "https://example.com/images/third.png")!
        let firstData = Data([1, 1, 1, 1])
        let secondData = Data([2, 2, 2, 2])
        let thirdData = Data([3, 3, 3, 3])
        let cache = ArticleImageDiskCache(
            directoryURL: directoryURL,
            capacityLimit: 8,
            dateProvider: { dateProvider.next() }
        )

        try await cache.insert(firstData, for: firstURL)
        try await cache.insert(secondData, for: secondURL)
        _ = try await cache.data(for: firstURL)
        try await cache.insert(thirdData, for: thirdURL)

        let retainedFirstData = try await cache.data(for: firstURL)
        let evictedSecondData = try await cache.data(for: secondURL)
        let retainedThirdData = try await cache.data(for: thirdURL)
        #expect(retainedFirstData == firstData)
        #expect(evictedSecondData == nil)
        #expect(retainedThirdData == thirdData)
    }

    @Test
    func boundedReadRemovesLegacyEntryLargerThanRequestedMaximum() async throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let imageURL = URL(string: "https://example.com/images/legacy-oversized.png")!
        let data = Data(repeating: 1, count: 33)
        let cache = ArticleImageDiskCache(directoryURL: directoryURL, capacityLimit: 1_024)

        try await cache.insert(data, for: imageURL)

        let boundedData = try await cache.data(for: imageURL, maximumBytes: 32)
        let remainingData = try await cache.data(for: imageURL)

        #expect(boundedData == nil)
        #expect(remainingData == nil)
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
}

private final class IncrementingDateProvider: @unchecked Sendable {
    private let lock = NSLock()
    private var currentTimeInterval: TimeInterval = 1_700_000_000

    func next() -> Date {
        lock.lock()
        defer { lock.unlock() }

        currentTimeInterval += 1
        return Date(timeIntervalSince1970: currentTimeInterval)
    }
}
