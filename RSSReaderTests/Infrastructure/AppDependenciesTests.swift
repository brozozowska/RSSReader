import CloudKit
import Foundation
import SwiftData
import Testing
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
