import CloudKit
import Foundation
import SwiftData
import Testing
@testable import RSSReader

@Suite("Infrastructure / AppDependencies / Remote Sync Reload / Recovery")
@MainActor
struct AppDependenciesRemoteSyncReloadRecoveryTests {
    @Test
    func appDependenciesStartRemoteSyncReloadAppLifetimeRequiresFreshRemoteChangeAfterImportFailure() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let logger = RecordingLogger()
        let syncCoordinator = SyncCoordinator(isSyncEnabled: true)
        syncCoordinator.applyAccountAvailability(.available)
        let cloudKitRuntimeEventSource = AppDependenciesTestCloudKitRuntimeEventSource()
        let remoteChangeSource = AppDependenciesTestPersistentStoreRemoteChangeSource()
        let dependencies = AppDependencies(
            logger: logger,
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

        try await remoteChangeSource.yieldAndWait(
            PersistentStoreRemoteChangeEvent(
                storeUUID: "SyncBackedStore",
                storeURL: URL(string: "file:///tmp/SyncBackedStore.sqlite")
            )
        )
        try await expectAppDependenciesEventually {
            logger.contains(
                "Observed persistent store remote change; marked store change pending",
                level: .info
            )
        }
        try await cloudKitRuntimeEventSource.yieldAndWait(
            .failed(
                .import,
                CloudKitRuntimeEventContext(
                    identifier: UUID(),
                    storeIdentifier: "SyncBackedStore",
                    startDate: .distantPast,
                    endDate: .now
                ),
                "Import failed."
            )
        )
        try await expectAppDependenciesEventually {
            logger.contains(
                "Observed CloudKit import failure; cleared pending remote reload correlation",
                level: .error
            )
        }
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

        expectAppDependenciesNoReload(
            sidebarReloadID: initialSidebarReloadID,
            articleListReloadID: initialArticleListReloadID,
            articleScreenReloadID: initialArticleScreenReloadID,
            in: appState
        )

        try await remoteChangeSource.yieldAndWait(
            PersistentStoreRemoteChangeEvent(
                storeUUID: "SyncBackedStore",
                storeURL: URL(string: "file:///tmp/SyncBackedStore.sqlite")
            )
        )

        try await expectAppDependenciesEventually {
            appState.sidebarReloadID != initialSidebarReloadID
                && appState.articleListReloadID != initialArticleListReloadID
                && appState.articleScreenReloadID != initialArticleScreenReloadID
        }
    }

    @Test
    func appDependenciesStartRemoteSyncReloadAppLifetimeRequiresFreshRemoteChangeAfterImportCancellation() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let logger = RecordingLogger()
        let syncCoordinator = SyncCoordinator(isSyncEnabled: true)
        syncCoordinator.applyAccountAvailability(.available)
        let cloudKitRuntimeEventSource = AppDependenciesTestCloudKitRuntimeEventSource()
        let remoteChangeSource = AppDependenciesTestPersistentStoreRemoteChangeSource()
        let dependencies = AppDependencies(
            logger: logger,
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

        try await remoteChangeSource.yieldAndWait(
            PersistentStoreRemoteChangeEvent(
                storeUUID: "SyncBackedStore",
                storeURL: URL(string: "file:///tmp/SyncBackedStore.sqlite")
            )
        )
        try await expectAppDependenciesEventually {
            logger.contains(
                "Observed persistent store remote change; marked store change pending",
                level: .info
            )
        }
        try await cloudKitRuntimeEventSource.yieldAndWait(
            .failed(
                .import,
                CloudKitRuntimeEventContext(
                    identifier: UUID(),
                    storeIdentifier: "SyncBackedStore",
                    startDate: .distantPast,
                    endDate: .now
                ),
                "cancelled"
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

        expectAppDependenciesNoReload(
            sidebarReloadID: initialSidebarReloadID,
            articleListReloadID: initialArticleListReloadID,
            articleScreenReloadID: initialArticleScreenReloadID,
            in: appState
        )

        try await remoteChangeSource.yieldAndWait(
            PersistentStoreRemoteChangeEvent(
                storeUUID: "SyncBackedStore",
                storeURL: URL(string: "file:///tmp/SyncBackedStore.sqlite")
            )
        )

        try await expectAppDependenciesEventually {
            appState.sidebarReloadID != initialSidebarReloadID
                && appState.articleListReloadID != initialArticleListReloadID
                && appState.articleScreenReloadID != initialArticleScreenReloadID
        }
    }
}
