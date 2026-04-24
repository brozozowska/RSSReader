import SwiftData
import Testing
@testable import RSSReader

@Suite("Infrastructure / AppDependencies")
@MainActor
struct AppDependenciesTests {
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
    func appDependenciesBuildSwiftDataContainerWithExplicitSyncAndLocalConfigurations() throws {
        let dependencies = AppDependencies.makeWithSwiftData(
            modelPartition: AppPersistenceModelPartition.current
        )

        let modelContainer = try #require(dependencies.modelContainer)
        #expect(modelContainer.configurations.count == 2)
    }
}
