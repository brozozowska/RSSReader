import CloudKit
import Foundation
import SwiftData
import Testing
@testable import RSSReader

@Suite("Infrastructure / AppDependencies / Composition")
@MainActor
struct AppDependenciesCompositionTests {
    @Test
    func appDependenciesExposeSeparateFolderRepositoryWhenSwiftDataIsAvailable() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())

        #expect(harness.dependencies.folderRepository != nil)
    }

    @Test
    func appDependenciesExposeSourceManagementServiceWhenSwiftDataIsAvailable() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())

        #expect(harness.dependencies.sourceManagementService != nil)
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
