import Foundation
import SwiftData
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
    func appCompositionSwiftDataFactoryBuildsAnIsolatedGraph() throws {
        let dependencies = makeIsolatedSwiftDataBootstrap(logger: TestLogger())

        let container = try #require(dependencies.modelContainer)
        #expect(container.configurations.count == 2)
        #expect(container.configurations.allSatisfy { $0.isStoredInMemoryOnly })
        #expect(dependencies.syncCoordinator != nil)
        #expect(dependencies.appSettingsService != nil)
        #expect(dependencies.syncBackedStoreReference == nil)
        #expect(dependencies.syncBootstrapContext?.modelContainerCloudKitPolicy == .disabled)
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
