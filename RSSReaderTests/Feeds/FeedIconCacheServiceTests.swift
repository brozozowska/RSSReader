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
