import CloudKit
import Foundation
import SwiftData
import Testing
@testable import RSSReader

@Suite("Infrastructure / AppDependencies / Remote Sync Reload")
@MainActor
struct AppDependenciesRemoteSyncReloadTests {
    @Test
    func appDependenciesStartRemoteSyncReloadAppLifetimeRequestsReloadWhenRemoteChangeAndImportCompletionArrive() async throws {
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
            appState.sourcesSidebarReloadID != initialSidebarReloadID
                && appState.articleListReloadID != initialArticleListReloadID
                && appState.articleScreenReloadID != initialArticleScreenReloadID
        }

        #expect(appState.lastContentReloadTrigger == .remoteSyncImport)
    }

    @Test
    func appDependenciesStartRemoteSyncReloadAppLifetimeRequestsReloadWhenImportCompletionArrivesBeforeRemoteChange() async throws {
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
        try await expectAppDependenciesRemoteSyncReloadObservationStarted(
            cloudKitRuntimeEventSource: cloudKitRuntimeEventSource,
            remoteChangeSource: remoteChangeSource
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
        await remoteChangeSource.yield(
            PersistentStoreRemoteChangeEvent(
                storeUUID: "SyncBackedStore",
                storeURL: URL(string: "file:///tmp/SyncBackedStore.sqlite")
            )
        )

        try await expectAppDependenciesEventually {
            appState.sourcesSidebarReloadID != initialSidebarReloadID
                && appState.articleListReloadID != initialArticleListReloadID
                && appState.articleScreenReloadID != initialArticleScreenReloadID
        }

        #expect(appState.lastContentReloadTrigger == .remoteSyncImport)
    }

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
            syncCoordinator: syncCoordinator
        )
        let appState = AppState()
        let initialSidebarReloadID = appState.sourcesSidebarReloadID
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
        try await expectAppDependenciesEventually {
            logger.contains(
                "Observed persistent store remote change; marked store change pending",
                level: .info
            )
        }
        await cloudKitRuntimeEventSource.yield(
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

        try await expectAppDependenciesNoReload(
            sidebarReloadID: initialSidebarReloadID,
            articleListReloadID: initialArticleListReloadID,
            articleScreenReloadID: initialArticleScreenReloadID,
            in: appState
        )

        await remoteChangeSource.yield(
            PersistentStoreRemoteChangeEvent(
                storeUUID: "SyncBackedStore",
                storeURL: URL(string: "file:///tmp/SyncBackedStore.sqlite")
            )
        )

        try await expectAppDependenciesEventually {
            appState.sourcesSidebarReloadID != initialSidebarReloadID
                && appState.articleListReloadID != initialArticleListReloadID
                && appState.articleScreenReloadID != initialArticleScreenReloadID
        }
    }

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
        let initialSidebarReloadID = appState.sourcesSidebarReloadID
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
        let initialSidebarReloadID = appState.sourcesSidebarReloadID
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

        #expect(appState.sourcesSidebarReloadID == initialSidebarReloadID)
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
        let initialSidebarReloadID = appState.sourcesSidebarReloadID
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

        #expect(appState.sourcesSidebarReloadID == initialSidebarReloadID)
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
        let initialSidebarReloadID = appState.sourcesSidebarReloadID
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
            appState.sourcesSidebarReloadID != initialSidebarReloadID
                && appState.articleListReloadID != initialArticleListReloadID
                && appState.articleScreenReloadID != initialArticleScreenReloadID
        }

        let firstSidebarReloadID = appState.sourcesSidebarReloadID
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

        #expect(appState.sourcesSidebarReloadID == firstSidebarReloadID)
        #expect(appState.articleListReloadID == firstArticleListReloadID)
        #expect(appState.articleScreenReloadID == firstArticleScreenReloadID)
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
            syncCoordinator: syncCoordinator
        )
        let appState = AppState()
        let initialSidebarReloadID = appState.sourcesSidebarReloadID
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
        try await expectAppDependenciesEventually {
            logger.contains(
                "Observed persistent store remote change; marked store change pending",
                level: .info
            )
        }
        await cloudKitRuntimeEventSource.yield(
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

        try await expectAppDependenciesNoReload(
            sidebarReloadID: initialSidebarReloadID,
            articleListReloadID: initialArticleListReloadID,
            articleScreenReloadID: initialArticleScreenReloadID,
            in: appState
        )

        await remoteChangeSource.yield(
            PersistentStoreRemoteChangeEvent(
                storeUUID: "SyncBackedStore",
                storeURL: URL(string: "file:///tmp/SyncBackedStore.sqlite")
            )
        )

        try await expectAppDependenciesEventually {
            appState.sourcesSidebarReloadID != initialSidebarReloadID
                && appState.articleListReloadID != initialArticleListReloadID
                && appState.articleScreenReloadID != initialArticleScreenReloadID
        }
    }

    @Test
    func appDependenciesRemoteSyncReloadLogsCorrelationEvents() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let logger = RecordingLogger()
        let syncCoordinator = SyncCoordinator(isSyncEnabled: true, logger: logger)
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
            syncCoordinator: syncCoordinator
        )
        let appState = AppState()

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
            logger.contains(
                "Requesting app-level remote sync reload after matching import completion and persistent store remote change for sync-backed storeIdentifier=SyncBackedStore"
            )
        }

        #expect(logger.contains("Starting remote sync reload app lifetime observation"))
        #expect(logger.contains("Observed persistent store remote change; marked store change pending"))
        #expect(logger.contains("Observed CloudKit import completion; marked import completion pending"))
    }
}
