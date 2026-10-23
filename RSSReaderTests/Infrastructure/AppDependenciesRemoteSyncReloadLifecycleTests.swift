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
            syncCoordinator: syncCoordinator,
            unreadAppIconBadgeService: NoOpUnreadAppIconBadgeService()
        )
        let appState = AppState()
        let initialSidebarReloadID = appState.sidebarReloadID
        let initialArticleListReloadID = appState.articleListReloadID
        let initialArticleScreenReloadID = appState.articleScreenReloadID

        dependencies.startRemoteSyncReloadAppLifetime(using: appState)
        try await expectAppDependenciesRemoteSyncReloadObservationStarted(
            cloudKitRuntimeEventSource: cloudKitRuntimeEventSource,
            remoteChangeSource: remoteChangeSource
        )
        dependencies.stopSyncRuntimeAppLifetime()
        try await waitUntil("remote reload subscriptions cancelled") {
            cloudKitRuntimeEventSource.subscriberCount == 0 && remoteChangeSource.subscriberCount == 0
        }

        try await remoteChangeSource.yieldAndWait(
            PersistentStoreRemoteChangeEvent(
                storeUUID: "SyncBackedStore",
                storeURL: URL(string: "file:///tmp/SyncBackedStore.sqlite")
            )
        )
        try await cloudKitRuntimeEventSource.yieldAndWait(
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

        #expect(appState.sidebarReloadID == initialSidebarReloadID)
        #expect(appState.articleListReloadID == initialArticleListReloadID)
        #expect(appState.articleScreenReloadID == initialArticleScreenReloadID)
    }
}
