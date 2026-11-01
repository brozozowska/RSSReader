import CloudKit
import Foundation
import SwiftData
import Testing
import UIKit
@testable import RSSReader

@Suite("Infrastructure / AppDependencies / Composition")
@MainActor
struct AppDependenciesCompositionTests {
    @Test
    func defaultImageRuntimesAreIndependentAndHaveNoLiveTransport() async throws {
        let first = AppDependencies(logger: TestLogger())
        let second = AppDependencies(logger: TestLogger())
        #expect(first.articleImageRuntime !== second.articleImageRuntime)
        let url = try #require(URL(string: "https://example.com/offline-preview.png"))
        await #expect(throws: URLError.self) {
            _ = try await first.articleImageRuntime.imageLoading.loadImage(
                from: url, displayTarget: .init(maximumPixelWidth: 32)
            )
        }
        #expect(try await first.articleImageCache.hasCachedImages() == false)
        #expect(try await second.articleImageCache.hasCachedImages() == false)
    }

    @Test
    func defaultGraphsAndHarnessesKeepIconsAndFolderPreferencesIndependent() async throws {
        try await expectFixtureIsolation(
            AppDependencies(logger: TestLogger()), AppDependencies(logger: TestLogger())
        )
        let first = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let second = try TestHarness.make(httpClient: ScriptedHTTPClient())
        try await expectFixtureIsolation(first.dependencies, second.dependencies)
        #expect(await first.httpClient.recordedRequests().isEmpty)
        #expect(await second.httpClient.recordedRequests().isEmpty)
    }

    @Test
    func fallbackHTTPIsOffline() async throws {
        let dependencies = AppDependencies.makeDefault()
        let url = try #require(URL(string: "https://example.com/icon.png"))
        do {
            _ = try await dependencies.httpClient.execute(HTTPRequest(url: url, maximumResponseBodyBytes: 1024))
            Issue.record("Expected offline dependency transport")
        } catch let error as URLError {
            #expect(error.code == .notConnectedToInternet)
        }
    }

    @Test
    func rootPreviewRefreshAndSettingsUseOnlyTheirFixtureOwners() async throws {
        let first = RootViewPreviewFactory.makeDependencies()
        let second = RootViewPreviewFactory.makeDependencies()
        try await expectFixtureIsolation(first, second)
        let feedID = RootViewPreviewFactory.SampleIDs.vergeFeedID
        let service = try #require(first.feedRefreshService)
        let result = await service.refresh(feedID: feedID)
        #expect(result.status == .fetched)
        #expect(try first.feedRepository?.fetchFeed(id: feedID)?.lastSuccessfulFetchAt != nil)
        #expect(try second.feedRepository?.fetchFeed(id: feedID)?.lastSuccessfulFetchAt == nil)
        #expect(try await first.feedIconCache.hasCachedData() == false)
        // Refresh reaches real icon discovery with an offline transport, while feed XML is local.
        #expect(try first.articleRepository?.fetchArticles(feedID: feedID).filter { $0.archivedAt == nil }.count == 1)
        #expect(try second.articleRepository?.fetchArticles(feedID: feedID).count == 2)
        let settings = SettingsScreenController()
        settings.loadSettings(dependencies: first)
        await settings.refreshFeedIconCacheAvailability(dependencies: first)
        #expect(settings.screenState.hasFeedIconCache == false)
    }

    @Test
    func suspendedIconDiscoveryPublishesToItsOwnGraphAndSettingsClearsOnlyThatGraph() async throws {
        let url = try #require(URL(string: "https://example.com/fixture-icon.png"))
        let feedURL = "https://example.com/fixture-feed.xml"
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let bytes = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16), format: format).pngData {
            $0.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        }
        let gate = ScriptedHTTPClientResponseGate()
        let client = ScriptedHTTPClient(responsesByURL: [
            feedURL: .response(statusCode: 200, headers: ["Content-Type": "application/rss+xml"], body: """
                <rss version="2.0"><channel><title>Fixture</title><link>https://example.com</link>
                <description>Local feed</description><image><url>\(url.absoluteString)</url>
                <title>Fixture</title><link>https://example.com</link></image></channel></rss>
                """),
            url.absoluteString: .gatedDataResponse(
                statusCode: 200, headers: ["Content-Type": "image/png"], body: bytes, gate: gate
            )
        ])
        let harness = try TestHarness.make(httpClient: client)
        let feed = try harness.insertFeeds(urls: [feedURL])[0]
        // Exercise the default discovery/cache wiring rather than the harness's no-op discovery.
        let first = AppDependencies(logger: TestLogger(), httpClient: client, modelContainer: harness.modelContainer)
        let second = try TestHarness.make(httpClient: ScriptedHTTPClient()).dependencies
        let otherBytes = Data("other fixture".utf8)
        try await second.feedIconCache.storeImageData(otherBytes, for: url)
        let service = try #require(first.feedRefreshService)
        let refresh = Task { await service.refresh(feedID: feed.id) }
        do {
            try await waitUntil("icon discovery suspended") { await gate.hasEntered() }
        } catch {
            await gate.release()
            _ = await refresh.value
            throw error
        }
        let settings = SettingsScreenController()
        await settings.handleButtonTap(itemID: .clearFeedIconCache, dependencies: first, appState: AppState())
        #expect(try await second.feedIconCache.cachedImageData(for: url) == otherBytes)
        await gate.release()
        let result = await refresh.value
        #expect(result.status == .fetched)
        #expect(try await first.feedIconCache.cachedImageData(for: url) == bytes)
        #expect(try await second.feedIconCache.cachedImageData(for: url) == otherBytes)
        #expect(await client.recordedRequests().map(\.url.absoluteString) == [feedURL, url.absoluteString])
        await settings.refreshFeedIconCacheAvailability(dependencies: first)
        #expect(settings.screenState.hasFeedIconCache)
        await settings.handleButtonTap(itemID: .clearFeedIconCache, dependencies: first, appState: AppState())
        #expect(try await first.feedIconCache.hasCachedData() == false)
        #expect(try await second.feedIconCache.cachedImageData(for: url) == otherBytes)
    }

    private func expectFixtureIsolation(_ first: AppDependencies, _ second: AppDependencies) async throws {
        let url = try #require(URL(string: "https://example.com/shared-fixture-icon.png"))
        let folderID = UUID()
        #expect(first.sidebarFolderExpansionStore.collapsedFolderIDs.isEmpty)
        #expect(second.sidebarFolderExpansionStore.collapsedFolderIDs.isEmpty)
        first.sidebarFolderExpansionStore.toggleExpansion(folderID: folderID)
        #expect(first.sidebarFolderExpansionStore.collapsedFolderIDs == [folderID])
        #expect(second.sidebarFolderExpansionStore.collapsedFolderIDs.isEmpty)
        try await first.feedIconCache.storeImageData(Data([1]), for: url)
        #expect(try await second.feedIconCache.cachedImageData(for: url) == nil)
        try await second.feedIconCache.storeImageData(Data([2]), for: url)
        let settings = SettingsScreenController()
        await settings.handleButtonTap(itemID: .clearFeedIconCache, dependencies: first, appState: AppState())
        #expect(try await first.feedIconCache.cachedImageData(for: url) == nil)
        #expect(try await second.feedIconCache.cachedImageData(for: url) == Data([2]))
        try await second.feedIconCache.removeAllCachedData()
    }

    @Test
    func appDependenciesExposeSeparateFolderRepositoryWhenSwiftDataIsAvailable() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())

        #expect(harness.dependencies.folderRepository != nil)
    }

    @Test
    func appDependenciesExposeFeedManagementServiceWhenSwiftDataIsAvailable() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())

        #expect(harness.dependencies.feedManagementService != nil)
    }

    @Test
    func appDependenciesExposeCloudKitRuntimeEventSource() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())

        _ = harness.dependencies.cloudKitRuntimeEventSource
    }

    @Test
    func appDependenciesExposeInjectedSyncCoordinator() throws {
        let syncCoordinator = SyncCoordinator()
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let dependencies = AppDependencies(
            logger: TestLogger(),
            httpClient: harness.httpClient,
            modelContainer: harness.modelContainer,
            syncCoordinator: syncCoordinator
        )

        #expect(dependencies.syncCoordinator === syncCoordinator)
    }

    @Test
    func appDependenciesExposeBackgroundRefreshRuntimePrerequisitesSnapshot() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let dependencies = AppDependencies(
            logger: TestLogger(),
            httpClient: harness.httpClient,
            modelContainer: harness.modelContainer
        )

        let snapshot = dependencies.currentBackgroundRefreshRuntimePrerequisites()

        #expect(snapshot.refreshIntervalPreference == .manual)
        #expect(snapshot.schedulingMode == .manual)
    }
}
