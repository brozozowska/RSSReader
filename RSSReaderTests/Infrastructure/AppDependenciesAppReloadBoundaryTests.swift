import CloudKit
import Foundation
import SwiftData
import Testing
@testable import RSSReader

@Suite("Infrastructure / AppDependencies / App Reload Boundaries")
@MainActor
struct AppDependenciesAppReloadBoundaryTests {
    @Test
    func appLevelReloadBoundaryKeepsRemoteSyncAndBackgroundRefreshTriggersSeparateAfterDiagnosticsCleanup() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let syncCoordinator = SyncCoordinator(isSyncEnabled: true)
        syncCoordinator.applyAccountAvailability(.available)
        let cloudKitRuntimeEventSource = AppDependenciesTestCloudKitRuntimeEventSource()
        let remoteChangeSource = AppDependenciesTestPersistentStoreRemoteChangeSource()
        let backgroundRefreshHandoffCoordinator = AppDependenciesRecordingBackgroundRefreshForegroundHandoffCoordinator()
        let dependencies = AppDependencies(
            logger: TestLogger(),
            httpClient: harness.httpClient,
            modelContainer: harness.modelContainer,
            syncBackedStoreReference: appDependenciesTestSyncBackedStoreReference(),
            backgroundRefreshForegroundHandoffCoordinator: backgroundRefreshHandoffCoordinator,
            cloudKitRuntimeEventSource: cloudKitRuntimeEventSource,
            persistentStoreRemoteChangeSource: remoteChangeSource,
            syncCoordinator: syncCoordinator,
            unreadAppIconBadgeService: NoOpUnreadAppIconBadgeService()
        )
        let appState = AppState()
        let initialSidebarReloadID = appState.sidebarReloadID
        let initialArticleListReloadID = appState.articleListReloadID
        let initialArticleScreenReloadID = appState.articleScreenReloadID

        AppComposition.bindBackgroundRefreshForegroundReloadHandler(
            using: dependencies,
            appState: appState
        )
        dependencies.startRemoteSyncReloadAppLifetime(using: appState)
        try await expectAppDependenciesRemoteSyncReloadObservationStarted(
            cloudKitRuntimeEventSource: cloudKitRuntimeEventSource,
            remoteChangeSource: remoteChangeSource
        )

        backgroundRefreshHandoffCoordinator.triggerBoundReloadHandler()

        #expect(appState.lastContentReloadTrigger == .backgroundRefresh)
        #expect(appState.sidebarReloadID != initialSidebarReloadID)
        #expect(appState.articleListReloadID != initialArticleListReloadID)
        #expect(appState.articleScreenReloadID != initialArticleScreenReloadID)

        let backgroundRefreshSidebarReloadID = appState.sidebarReloadID
        let backgroundRefreshArticleListReloadID = appState.articleListReloadID
        let backgroundRefreshArticleScreenReloadID = appState.articleScreenReloadID

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

        try await expectAppDependenciesEventually {
            appState.lastContentReloadTrigger == .remoteSyncImport
                && appState.sidebarReloadID != backgroundRefreshSidebarReloadID
                && appState.articleListReloadID != backgroundRefreshArticleListReloadID
                && appState.articleScreenReloadID != backgroundRefreshArticleScreenReloadID
        }
    }
}
