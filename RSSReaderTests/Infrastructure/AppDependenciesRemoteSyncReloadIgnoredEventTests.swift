import CloudKit
import Foundation
import SwiftData
import Testing
@testable import RSSReader

@Suite("Infrastructure / AppDependencies / Remote Sync Reload / Ignored Events")
@MainActor
struct AppDependenciesRemoteSyncReloadIgnoredEventTests {
    @Test
    func appDependenciesStartRemoteSyncReloadAppLifetimeDoesNotReloadForExportCompletion() async throws {
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
        let initialSidebarReloadID = appState.sidebarReloadID
        let initialArticleListReloadID = appState.articleListReloadID
        let initialArticleScreenReloadID = appState.articleScreenReloadID

        dependencies.startRemoteSyncReloadAppLifetime(using: appState)
        try await expectAppDependenciesRemoteSyncReloadObservationStarted(
            cloudKitRuntimeEventSource: cloudKitRuntimeEventSource,
            remoteChangeSource: remoteChangeSource
        )

        await remoteChangeSource.yield(
            PersistentStoreRemoteChangeEvent(
                storeUUID: "SyncBackedStore",
                storeURL: URL(string: "file:///tmp/SyncBackedStore.sqlite")
            )
        )
        await cloudKitRuntimeEventSource.yield(
            .finished(
                .export,
                CloudKitRuntimeEventContext(
                    identifier: UUID(),
                    storeIdentifier: "SyncBackedStore",
                    startDate: .distantPast,
                    endDate: .now
                )
            )
        )

        try await expectAppDependenciesNoReload(
            sidebarReloadID: initialSidebarReloadID,
            articleListReloadID: initialArticleListReloadID,
            articleScreenReloadID: initialArticleScreenReloadID,
            in: appState
        )
    }

    @Test
    func appDependenciesStartRemoteSyncReloadAppLifetimeDoesNotReloadForMismatchedRemoteChangeStore() async throws {
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
        let initialSidebarReloadID = appState.sidebarReloadID
        let initialArticleListReloadID = appState.articleListReloadID
        let initialArticleScreenReloadID = appState.articleScreenReloadID

        dependencies.startRemoteSyncReloadAppLifetime(using: appState)
        try await expectAppDependenciesRemoteSyncReloadObservationStarted(
            cloudKitRuntimeEventSource: cloudKitRuntimeEventSource,
            remoteChangeSource: remoteChangeSource
        )

        await remoteChangeSource.yield(
            PersistentStoreRemoteChangeEvent(
                storeUUID: "LocalOnlyStore",
                storeURL: URL(string: "file:///tmp/LocalOnlyStore.sqlite")
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

        #expect(appState.sidebarReloadID == initialSidebarReloadID)
        #expect(appState.articleListReloadID == initialArticleListReloadID)
        #expect(appState.articleScreenReloadID == initialArticleScreenReloadID)
    }

    @Test
    func appDependenciesStartRemoteSyncReloadAppLifetimeDoesNotReloadForMismatchedImportStoreIdentifier() async throws {
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
        let initialSidebarReloadID = appState.sidebarReloadID
        let initialArticleListReloadID = appState.articleListReloadID
        let initialArticleScreenReloadID = appState.articleScreenReloadID

        dependencies.startRemoteSyncReloadAppLifetime(using: appState)
        try await expectAppDependenciesRemoteSyncReloadObservationStarted(
            cloudKitRuntimeEventSource: cloudKitRuntimeEventSource,
            remoteChangeSource: remoteChangeSource
        )

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
                    storeIdentifier: "LocalOnlyStore",
                    startDate: .distantPast,
                    endDate: .now
                )
            )
        )

        try await Task.sleep(for: .milliseconds(100))

        #expect(appState.sidebarReloadID == initialSidebarReloadID)
        #expect(appState.articleListReloadID == initialArticleListReloadID)
        #expect(appState.articleScreenReloadID == initialArticleScreenReloadID)
    }

    @Test
    func appDependenciesStartRemoteSyncReloadAppLifetimeDoesNotReloadTwiceForRepeatedImportCompletionWithoutNewRemoteChange() async throws {
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
        let initialSidebarReloadID = appState.sidebarReloadID
        let initialArticleListReloadID = appState.articleListReloadID
        let initialArticleScreenReloadID = appState.articleScreenReloadID

        dependencies.startRemoteSyncReloadAppLifetime(using: appState)
        try await expectAppDependenciesRemoteSyncReloadObservationStarted(
            cloudKitRuntimeEventSource: cloudKitRuntimeEventSource,
            remoteChangeSource: remoteChangeSource
        )

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
            appState.sidebarReloadID != initialSidebarReloadID
                && appState.articleListReloadID != initialArticleListReloadID
                && appState.articleScreenReloadID != initialArticleScreenReloadID
        }

        let firstSidebarReloadID = appState.sidebarReloadID
        let firstArticleListReloadID = appState.articleListReloadID
        let firstArticleScreenReloadID = appState.articleScreenReloadID

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

        #expect(appState.sidebarReloadID == firstSidebarReloadID)
        #expect(appState.articleListReloadID == firstArticleListReloadID)
        #expect(appState.articleScreenReloadID == firstArticleScreenReloadID)
    }
}
