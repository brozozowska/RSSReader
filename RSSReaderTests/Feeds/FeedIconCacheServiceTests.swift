import Foundation
import Testing
@testable import RSSReader

@Suite("Feeds / Feed Icon Cache")
@MainActor
struct FeedIconCacheServiceTests {
    @Test
    func feedIconCacheReturnsCachedDataWithoutSecondNetworkRequest() async throws {
        let iconURL = try #require(URL(string: "https://example.com/favicon.ico"))
        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let diskCache = FeedIconDiskCache(directoryURL: directoryURL, capacityLimit: 1_024)
        let httpClient = ScriptedHTTPClient(
            responsesByURL: [
                iconURL.absoluteString: .response(
                    statusCode: 200,
                    headers: ["Content-Type": "image/x-icon"],
                    body: "icon-binary"
                )
            ]
        )
        let service = FeedIconCacheService(httpClient: httpClient, diskCache: diskCache)

        let firstLoad = try await service.imageData(for: iconURL)
        let secondLoad = try await service.imageData(for: iconURL)

        #expect(firstLoad == Data("icon-binary".utf8))
        #expect(secondLoad == firstLoad)

        let requests = await httpClient.recordedRequests()
        #expect(requests.count == 1)
    }

    @Test
    func feedIconCacheSharesInFlightRequestBetweenConcurrentConsumers() async throws {
        let iconURL = try #require(URL(string: "https://example.com/favicon.ico"))
        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let diskCache = FeedIconDiskCache(directoryURL: directoryURL, capacityLimit: 1_024)
        let httpClient = ScriptedHTTPClient(
            responsesByURL: [
                iconURL.absoluteString: .delayedResponse(
                    statusCode: 200,
                    headers: ["Content-Type": "image/x-icon"],
                    body: "icon-binary",
                    delayNanoseconds: 50_000_000
                )
            ]
        )
        let service = FeedIconCacheService(httpClient: httpClient, diskCache: diskCache)

        async let firstLoad = service.imageData(for: iconURL)
        async let secondLoad = service.imageData(for: iconURL)
        let (firstResult, secondResult) = try await (firstLoad, secondLoad)

        #expect(firstResult == secondResult)

        let requests = await httpClient.recordedRequests()
        #expect(requests.count == 1)
        #expect(await httpClient.maxConcurrentExecutions() == 1)
    }

    @Test
    func feedIconCacheRestoresDataFromDiskWithoutNetworkAfterRelaunch() async throws {
        let iconURL = try #require(URL(string: "https://example.com/apple-touch-icon.png"))
        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let diskCache = FeedIconDiskCache(directoryURL: directoryURL, capacityLimit: 1_024)
        let firstHTTPClient = ScriptedHTTPClient(
            responsesByURL: [
                iconURL.absoluteString: .response(
                    statusCode: 200,
                    headers: ["Content-Type": "image/png"],
                    body: "persisted-icon"
                )
            ]
        )
        let firstService = FeedIconCacheService(httpClient: firstHTTPClient, diskCache: diskCache)

        let firstLoad = try await firstService.imageData(for: iconURL)

        let secondHTTPClient = ScriptedHTTPClient()
        let restoredDiskCache = FeedIconDiskCache(directoryURL: directoryURL, capacityLimit: 1_024)
        let restoredService = FeedIconCacheService(httpClient: secondHTTPClient, diskCache: restoredDiskCache)
        let restoredLoad = try await restoredService.imageData(for: iconURL)
        let secondRequests = await secondHTTPClient.recordedRequests()

        #expect(firstLoad == Data("persisted-icon".utf8))
        #expect(restoredLoad == firstLoad)
        #expect(try await restoredService.hasCachedData())
        #expect(secondRequests.isEmpty)
    }

    @Test
    func feedIconCacheOnlyLookupDoesNotStartNetworkRequestForMissingIcon() async throws {
        let iconURL = try #require(URL(string: "https://example.com/favicon.ico"))
        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let diskCache = FeedIconDiskCache(directoryURL: directoryURL, capacityLimit: 1_024)
        let httpClient = ScriptedHTTPClient(
            responsesByURL: [
                iconURL.absoluteString: .response(
                    statusCode: 200,
                    headers: ["Content-Type": "image/x-icon"],
                    body: "icon-binary"
                )
            ]
        )
        let service = FeedIconCacheService(httpClient: httpClient, diskCache: diskCache)

        let cachedData = try await service.cachedImageData(for: iconURL)
        let requests = await httpClient.recordedRequests()

        #expect(cachedData == nil)
        #expect(requests.isEmpty)
    }

    @Test
    func feedIconCacheStoresDownloadedDataUnderAliasURL() async throws {
        let discoveredIconURL = try #require(URL(string: "https://example.com/assets/apple-touch-icon.png"))
        let stableIconURL = try #require(URL(string: "https://example.com/favicon.ico"))
        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let diskCache = FeedIconDiskCache(directoryURL: directoryURL, capacityLimit: 1_024)
        let httpClient = ScriptedHTTPClient(
            responsesByURL: [
                discoveredIconURL.absoluteString: .response(
                    statusCode: 200,
                    headers: ["Content-Type": "image/png"],
                    body: "discovered-icon"
                )
            ]
        )
        let service = FeedIconCacheService(httpClient: httpClient, diskCache: diskCache)

        let downloadedData = try await service.imageData(for: discoveredIconURL)
        try await service.storeImageData(downloadedData, for: stableIconURL)

        let restoredDiskCache = FeedIconDiskCache(directoryURL: directoryURL, capacityLimit: 1_024)
        let restoredService = FeedIconCacheService(
            httpClient: ScriptedHTTPClient(),
            diskCache: restoredDiskCache
        )
        let restoredAliasData = try await restoredService.cachedImageData(for: stableIconURL)

        #expect(restoredAliasData == Data("discovered-icon".utf8))
    }

    @Test
    func feedIconCacheClearRemovesMemoryAndDiskData() async throws {
        let iconURL = try #require(URL(string: "https://example.com/favicon.ico"))
        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let diskCache = FeedIconDiskCache(directoryURL: directoryURL, capacityLimit: 1_024)
        let httpClient = ScriptedHTTPClient(
            responsesByURL: [
                iconURL.absoluteString: .response(
                    statusCode: 200,
                    headers: ["Content-Type": "image/x-icon"],
                    body: "first-icon"
                )
            ]
        )
        let service = FeedIconCacheService(httpClient: httpClient, diskCache: diskCache)

        _ = try await service.imageData(for: iconURL)
        try await service.removeAllCachedData()

        #expect(try await service.hasCachedData() == false)
        #expect(try await diskCache.isEmpty())
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
