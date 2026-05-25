import Foundation
import Testing
@testable import RSSReader

@Suite("Feeds / Source Icon Cache")
@MainActor
struct SourceIconCacheServiceTests {
    @Test
    func sourceIconCacheReturnsCachedDataWithoutSecondNetworkRequest() async throws {
        let iconURL = try #require(URL(string: "https://example.com/favicon.ico"))
        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let diskCache = SourceIconDiskCache(directoryURL: directoryURL, capacityLimit: 1_024)
        let httpClient = ScriptedHTTPClient(
            responsesByURL: [
                iconURL.absoluteString: .response(
                    statusCode: 200,
                    headers: ["Content-Type": "image/x-icon"],
                    body: "icon-binary"
                )
            ]
        )
        let service = SourceIconCacheService(httpClient: httpClient, diskCache: diskCache)

        let firstLoad = try await service.imageData(for: iconURL)
        let secondLoad = try await service.imageData(for: iconURL)

        #expect(firstLoad == Data("icon-binary".utf8))
        #expect(secondLoad == firstLoad)

        let requests = await httpClient.recordedRequests()
        #expect(requests.count == 1)
    }

    @Test
    func sourceIconCacheSharesInFlightRequestBetweenConcurrentConsumers() async throws {
        let iconURL = try #require(URL(string: "https://example.com/favicon.ico"))
        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let diskCache = SourceIconDiskCache(directoryURL: directoryURL, capacityLimit: 1_024)
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
        let service = SourceIconCacheService(httpClient: httpClient, diskCache: diskCache)

        async let firstLoad = service.imageData(for: iconURL)
        async let secondLoad = service.imageData(for: iconURL)
        let (firstResult, secondResult) = try await (firstLoad, secondLoad)

        #expect(firstResult == secondResult)

        let requests = await httpClient.recordedRequests()
        #expect(requests.count == 1)
        #expect(await httpClient.maxConcurrentExecutions() == 1)
    }

    @Test
    func sourceIconCacheRestoresDataFromDiskWithoutNetworkAfterRelaunch() async throws {
        let iconURL = try #require(URL(string: "https://example.com/apple-touch-icon.png"))
        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let diskCache = SourceIconDiskCache(directoryURL: directoryURL, capacityLimit: 1_024)
        let firstHTTPClient = ScriptedHTTPClient(
            responsesByURL: [
                iconURL.absoluteString: .response(
                    statusCode: 200,
                    headers: ["Content-Type": "image/png"],
                    body: "persisted-icon"
                )
            ]
        )
        let firstService = SourceIconCacheService(httpClient: firstHTTPClient, diskCache: diskCache)

        let firstLoad = try await firstService.imageData(for: iconURL)

        let secondHTTPClient = ScriptedHTTPClient()
        let restoredDiskCache = SourceIconDiskCache(directoryURL: directoryURL, capacityLimit: 1_024)
        let restoredService = SourceIconCacheService(httpClient: secondHTTPClient, diskCache: restoredDiskCache)
        let restoredLoad = try await restoredService.imageData(for: iconURL)
        let secondRequests = await secondHTTPClient.recordedRequests()

        #expect(firstLoad == Data("persisted-icon".utf8))
        #expect(restoredLoad == firstLoad)
        #expect(try await restoredService.hasCachedData())
        #expect(secondRequests.isEmpty)
    }

    @Test
    func sourceIconCacheOnlyLookupDoesNotStartNetworkRequestForMissingIcon() async throws {
        let iconURL = try #require(URL(string: "https://example.com/favicon.ico"))
        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let diskCache = SourceIconDiskCache(directoryURL: directoryURL, capacityLimit: 1_024)
        let httpClient = ScriptedHTTPClient(
            responsesByURL: [
                iconURL.absoluteString: .response(
                    statusCode: 200,
                    headers: ["Content-Type": "image/x-icon"],
                    body: "icon-binary"
                )
            ]
        )
        let service = SourceIconCacheService(httpClient: httpClient, diskCache: diskCache)

        let cachedData = try await service.cachedImageData(for: iconURL)
        let requests = await httpClient.recordedRequests()

        #expect(cachedData == nil)
        #expect(requests.isEmpty)
    }

    @Test
    func sourceIconCacheStoresDownloadedDataUnderAliasURL() async throws {
        let discoveredIconURL = try #require(URL(string: "https://example.com/assets/apple-touch-icon.png"))
        let stableIconURL = try #require(URL(string: "https://example.com/favicon.ico"))
        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let diskCache = SourceIconDiskCache(directoryURL: directoryURL, capacityLimit: 1_024)
        let httpClient = ScriptedHTTPClient(
            responsesByURL: [
                discoveredIconURL.absoluteString: .response(
                    statusCode: 200,
                    headers: ["Content-Type": "image/png"],
                    body: "discovered-icon"
                )
            ]
        )
        let service = SourceIconCacheService(httpClient: httpClient, diskCache: diskCache)

        let downloadedData = try await service.imageData(for: discoveredIconURL)
        try await service.storeImageData(downloadedData, for: stableIconURL)

        let restoredDiskCache = SourceIconDiskCache(directoryURL: directoryURL, capacityLimit: 1_024)
        let restoredService = SourceIconCacheService(
            httpClient: ScriptedHTTPClient(),
            diskCache: restoredDiskCache
        )
        let restoredAliasData = try await restoredService.cachedImageData(for: stableIconURL)

        #expect(restoredAliasData == Data("discovered-icon".utf8))
    }

    @Test
    func sourceIconCacheClearRemovesMemoryAndDiskData() async throws {
        let iconURL = try #require(URL(string: "https://example.com/favicon.ico"))
        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let diskCache = SourceIconDiskCache(directoryURL: directoryURL, capacityLimit: 1_024)
        let httpClient = ScriptedHTTPClient(
            responsesByURL: [
                iconURL.absoluteString: .response(
                    statusCode: 200,
                    headers: ["Content-Type": "image/x-icon"],
                    body: "first-icon"
                )
            ]
        )
        let service = SourceIconCacheService(httpClient: httpClient, diskCache: diskCache)

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
