import CloudKit
import Foundation
import SwiftData
import Testing
@testable import RSSReader

@Suite("Infrastructure / AppDependencies / Remote Sync Reload / Logging")
@MainActor
struct AppDependenciesRemoteSyncReloadLoggingTests {
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
