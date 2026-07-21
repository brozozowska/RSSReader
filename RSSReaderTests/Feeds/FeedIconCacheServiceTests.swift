import Foundation
import Testing
@testable import RSSReader

@Suite("Feeds / Feed Icon Cache")
@MainActor
struct FeedIconCacheServiceTests {
    @Test
    func cacheMissReturnsNilWithoutCreatingDiskData() async throws {
        let iconURL = try makeURL("https://example.com/favicon.ico")
        let harness = try makeHarness()

        let cachedData = try await harness.service.cachedImageData(for: iconURL)

        #expect(cachedData == nil)
        #expect(try await harness.service.hasCachedData() == false)
        #expect(try await harness.diskCache.isEmpty())
    }

    @Test
    func storedDataIsAvailableThroughCacheLookup() async throws {
        let iconURL = try makeURL("https://example.com/feed-icon.png")
        let iconData = Data("icon-binary".utf8)
        let harness = try makeHarness()

        try await harness.service.storeImageData(iconData, for: iconURL)

        #expect(try await harness.service.cachedImageData(for: iconURL) == iconData)
        #expect(try await harness.service.hasCachedData())
        #expect(try await harness.diskCache.isEmpty() == false)
    }

    @Test
    func memoryCacheServesStoredDataWhenDiskEntryIsRemoved() async throws {
        let iconURL = try makeURL("https://example.com/apple-touch-icon.png")
        let iconData = Data("memory-icon".utf8)
        let harness = try makeHarness()
        try await harness.service.storeImageData(iconData, for: iconURL)

        try await harness.diskCache.removeAll()

        #expect(try await harness.service.cachedImageData(for: iconURL) == iconData)
        #expect(try await harness.service.hasCachedData())
    }

    @Test
    func diskCacheRestoresStoredDataAfterServiceRelaunch() async throws {
        let iconURL = try makeURL("https://example.com/apple-touch-icon.png")
        let iconData = Data("persisted-icon".utf8)
        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let firstDiskCache = FeedIconDiskCache(directoryURL: directoryURL, capacityLimit: 1_024)
        let firstService = FeedIconCacheService(diskCache: firstDiskCache)
        try await firstService.storeImageData(iconData, for: iconURL)

        let restoredDiskCache = FeedIconDiskCache(directoryURL: directoryURL, capacityLimit: 1_024)
        let restoredService = FeedIconCacheService(diskCache: restoredDiskCache)

        #expect(try await restoredService.cachedImageData(for: iconURL) == iconData)
        #expect(try await restoredService.hasCachedData())
    }

    @Test
    func diskCacheDoesNotRetainSingleEntryLargerThanCapacity() async throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let iconURL = try makeURL("https://example.com/oversized-feed-icon.png")
        let diskCache = FeedIconDiskCache(directoryURL: directoryURL, capacityLimit: 4)

        try await diskCache.insert(Data(repeating: 1, count: 5), for: iconURL)

        #expect(try await diskCache.data(for: iconURL) == nil)
        #expect(try await diskCache.isEmpty())
    }

    @Test
    func diskCacheEvictsLeastRecentlyUsedEntryAcrossAggregateCapacity() async throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let dateProvider = FeedIconIncrementingDateProvider()
        let firstURL = try makeURL("https://example.com/first-feed-icon.png")
        let secondURL = try makeURL("https://example.com/second-feed-icon.png")
        let thirdURL = try makeURL("https://example.com/third-feed-icon.png")
        let firstData = Data(repeating: 1, count: 4)
        let secondData = Data(repeating: 2, count: 4)
        let thirdData = Data(repeating: 3, count: 4)
        let diskCache = FeedIconDiskCache(
            directoryURL: directoryURL,
            capacityLimit: 8,
            dateProvider: { dateProvider.next() }
        )

        try await diskCache.insert(firstData, for: firstURL)
        try await diskCache.insert(secondData, for: secondURL)
        _ = try await diskCache.data(for: firstURL)
        try await diskCache.insert(thirdData, for: thirdURL)

        #expect(try await diskCache.data(for: firstURL) == firstData)
        #expect(try await diskCache.data(for: secondURL) == nil)
        #expect(try await diskCache.data(for: thirdURL) == thirdData)
    }

    @Test
    func diskWriteFailureDoesNotPopulateFeedIconMemoryCache() async throws {
        let rootDirectoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectoryURL) }
        let blockingFileURL = rootDirectoryURL.appendingPathComponent("not-a-directory")
        let blockingData = Data("blocking-file".utf8)
        try blockingData.write(to: blockingFileURL)
        let iconURL = try makeURL("https://example.com/write-failure-feed-icon.png")
        let memoryCache = FeedIconMemoryCache(countLimit: 2)
        let diskCache = FeedIconDiskCache(
            directoryURL: blockingFileURL,
            capacityLimit: 1_024
        )
        let service = FeedIconCacheService(cache: memoryCache, diskCache: diskCache)

        do {
            try await service.storeImageData(Data("feed-icon".utf8), for: iconURL)
            Issue.record("Expected feed icon disk write failure")
        } catch {
            // Expected failure from a cache path that is a regular file.
        }

        #expect(await memoryCache.data(for: iconURL) == nil)
        #expect(await memoryCache.cachedEntryCount() == 0)
        #expect(try Data(contentsOf: blockingFileURL) == blockingData)
    }

    @Test
    func emptyDataIsRejectedWithoutCreatingCacheEntry() async throws {
        let iconURL = try makeURL("https://example.com/empty-icon.png")
        let harness = try makeHarness()

        do {
            try await harness.service.storeImageData(Data(), for: iconURL)
            Issue.record("Expected empty image data failure")
        } catch FeedIconCacheError.emptyImageData {
            // Expected cache-boundary validation.
        } catch {
            Issue.record("Expected FeedIconCacheError.emptyImageData, got \(error)")
        }

        #expect(try await harness.service.cachedImageData(for: iconURL) == nil)
        #expect(try await harness.service.hasCachedData() == false)
        #expect(try await harness.diskCache.isEmpty())
    }

    @Test
    func clearRemovesMemoryAndDiskData() async throws {
        let iconURL = try makeURL("https://example.com/favicon.ico")
        let harness = try makeHarness()
        try await harness.service.storeImageData(Data("first-icon".utf8), for: iconURL)

        try await harness.service.removeAllCachedData()

        #expect(try await harness.service.cachedImageData(for: iconURL) == nil)
        #expect(try await harness.service.hasCachedData() == false)
        #expect(try await harness.diskCache.isEmpty())
    }

    @Test
    func memoryCacheSynchronizesAutomaticEvictionWithHasCachedData() async throws {
        let cache = FeedIconMemoryCache(countLimit: 1)
        let firstURL = try makeURL("https://example.com/first-icon.png")
        let secondURL = try makeURL("https://example.com/second-icon.png")

        await cache.insert(Data("first".utf8), for: firstURL)
        await cache.insert(Data("second".utf8), for: secondURL)

        let firstValue = await cache.data(for: firstURL)
        let secondValue = await cache.data(for: secondURL)
        #expect([firstValue, secondValue].compactMap { $0 }.count == 1)
        #expect(await cache.cachedEntryCount() == 1)
        #expect(await cache.hasCachedData())
    }

    @Test
    func memoryCacheEnforcesAggregateByteCostAndKeepsBookkeepingSynchronized() async throws {
        let cache = FeedIconMemoryCache(countLimit: 10, totalCostLimit: 8)
        let firstURL = try makeURL("https://example.com/cost-first-icon.png")
        let secondURL = try makeURL("https://example.com/cost-second-icon.png")
        let thirdURL = try makeURL("https://example.com/cost-third-icon.png")

        await cache.insert(Data(repeating: 1, count: 4), for: firstURL)
        await cache.insert(Data(repeating: 2, count: 4), for: secondURL)
        await cache.insert(Data(repeating: 3, count: 4), for: thirdURL)

        let firstValue = await cache.data(for: firstURL)
        let secondValue = await cache.data(for: secondURL)
        let thirdValue = await cache.data(for: thirdURL)
        let cachedValues = [firstValue, secondValue, thirdValue].compactMap { $0 }

        #expect(cachedValues.isEmpty == false)
        #expect(cachedValues.count <= 2)
        #expect(await cache.cachedEntryCount() == cachedValues.count)
        #expect(await cache.hasCachedData())
    }

    private func makeHarness() throws -> FeedIconCacheHarness {
        let directoryURL = try makeTemporaryDirectory()
        let diskCache = FeedIconDiskCache(directoryURL: directoryURL, capacityLimit: 1_024)
        return FeedIconCacheHarness(
            service: FeedIconCacheService(diskCache: diskCache),
            diskCache: diskCache,
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
}

private final class FeedIconCacheHarness {
    let service: FeedIconCacheService
    let diskCache: FeedIconDiskCache
    let directoryURL: URL

    init(
        service: FeedIconCacheService,
        diskCache: FeedIconDiskCache,
        directoryURL: URL
    ) {
        self.service = service
        self.diskCache = diskCache
        self.directoryURL = directoryURL
    }

    deinit {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}

private final class FeedIconIncrementingDateProvider: @unchecked Sendable {
    private let lock = NSLock()
    private var currentTimeInterval: TimeInterval = 1_700_000_000

    func next() -> Date {
        lock.lock()
        defer { lock.unlock() }

        currentTimeInterval += 1
        return Date(timeIntervalSince1970: currentTimeInterval)
    }
}
