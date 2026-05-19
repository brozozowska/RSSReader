import Foundation
import Testing
@testable import RSSReader

@Suite("Infrastructure / AppComposition")
@MainActor
struct AppCompositionTests {
    @Test
    func appCompositionAppliesCurrentICloudSyncStatusFromSyncCoordinatorToAppState() {
        let syncCoordinator = SyncCoordinator(isSyncEnabled: true)
        let appState = AppState()

        syncCoordinator.applyAccountAvailability(.available)
        AppComposition.applyCurrentICloudSyncStatus(from: syncCoordinator, to: appState)

        #expect(appState.iCloudSyncStatus == .idle)
    }

    @Test
    func appCompositionLeavesAppStateUntouchedWhenSyncCoordinatorIsUnavailable() {
        let appState = AppState()
        appState.applyICloudSyncStatus(.syncing)

        AppComposition.applyCurrentICloudSyncStatus(from: nil, to: appState)

        #expect(appState.iCloudSyncStatus == .syncing)
    }

    @Test
    func appCompositionMakeAppDependenciesUsesUnifiedSwiftDataBootstrapPath() {
        let dependencies = AppComposition.makeAppDependencies(
            modelPartition: AppComposition.persistenceModelPartition
        )

        #expect(dependencies.modelContainer != nil)
        #expect(dependencies.syncCoordinator != nil)
        #expect(dependencies.appSettingsService != nil)
    }

    @Test
    func appCompositionArticleImageURLCacheConfigurationUsesBoundedMemoryAndDiskCache() {
        let configuration = AppURLCacheConfiguration.articleImageLoading
        let cache = configuration.makeURLCache()

        #expect(configuration.memoryCapacity == 50 * 1024 * 1024)
        #expect(configuration.diskCapacity == 200 * 1024 * 1024)
        #expect(configuration.diskPath == "RSSReaderArticleImageURLCache")
        #expect(cache.memoryCapacity == configuration.memoryCapacity)
        #expect(cache.diskCapacity == configuration.diskCapacity)
    }

    @Test
    func appCompositionDevelopmentSchemaBootstrapGuardRunsBootstrapOnlyOncePerLaunch() {
        let logger = RecordingLogger()
        let bootstrapGuard = AppLaunchBootstrapGuard()
        var bootstrapRunCount = 0

        AppComposition.runDevelopmentSchemaBootstrapIfNeeded(
            logger: logger,
            guard: bootstrapGuard
        ) { _ in
            bootstrapRunCount += 1
        }

        AppComposition.runDevelopmentSchemaBootstrapIfNeeded(
            logger: logger,
            guard: bootstrapGuard
        ) { _ in
            bootstrapRunCount += 1
        }

        #expect(bootstrapRunCount == 1)
        #expect(
            logger.contains(
                "Skipped CloudKit development schema bootstrap because app launch guard already attempted it",
                level: .debug
            )
        )
    }
}
