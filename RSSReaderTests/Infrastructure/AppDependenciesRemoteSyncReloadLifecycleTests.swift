import CloudKit
import Foundation
import SwiftData
import Testing
@testable import RSSReader

@Suite("Infrastructure / AppDependencies / Remote Sync Reload Lifecycle")
@MainActor
struct AppDependenciesRemoteSyncReloadLifecycleTests {
    @Test
    func appDependenciesStopSyncRuntimeAppLifetimeCancelsRemoteReloadObservation() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let syncCoordinator = SyncCoordinator(isSyncEnabled: true)
        syncCoordinator.applyAccountAvailability(.available)
        let cloudKitRuntimeEventSource = AppDependenciesTestCloudKitRuntimeEventSource()
        let remoteChangeSource = AppDependenciesTestPersistentStoreRemoteChangeSource()
        let dependencies = AppDependencies(
            logger: TestLogger(),
            httpClient: harness.httpClient,
            modelContainer: harness.modelContainer,
            syncBackedStoreReference: appDependenciesTestSyncBackedStoreReference(),
            cloudKitRuntimeEventSource: cloudKitRuntimeEventSource,
            persistentStoreRemoteChangeSource: remoteChangeSource,
            syncCoordinator: syncCoordinator
        )
        let appState = AppState()
        let initialSidebarReloadID = appState.sourcesSidebarReloadID
        let initialArticleListReloadID = appState.articleListReloadID
        let initialArticleScreenReloadID = appState.articleScreenReloadID

        dependencies.startRemoteSyncReloadAppLifetime(using: appState)
        dependencies.stopSyncRuntimeAppLifetime()

        await remoteChangeSource.yield(
            PersistentStoreRemoteChangeEvent(
                storeUUID: "SyncBackedStore",
                storeURL: URL(string: "file:///tmp/SyncBackedStore.sqlite")
            )
        )
        await cloudKitRuntimeEventSource.yield(
            .finished(
                .import,
                CloudKitRuntimeEventContext(
                    identifier: UUID(),
                    storeIdentifier: "SyncBackedStore",
                    startDate: .distantPast,
                    endDate: .now
                )
            )
        )

        try await Task.sleep(for: .milliseconds(100))

        #expect(appState.sourcesSidebarReloadID == initialSidebarReloadID)
        #expect(appState.articleListReloadID == initialArticleListReloadID)
        #expect(appState.articleScreenReloadID == initialArticleScreenReloadID)
    }
}
