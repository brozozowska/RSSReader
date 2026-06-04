import CloudKit
import Foundation
import SwiftData
import Testing
@testable import RSSReader

@Suite("Infrastructure / AppDependencies / SwiftData Bootstrap Diagnostics")
@MainActor
struct AppDependenciesSwiftDataBootstrapDiagnosticsTests {
    @Test
    func appDependenciesMakeWithSwiftDataLogsModelContainerSetupMarkers() {
        let logger = RecordingLogger()
        let syncCoordinator = SyncCoordinator(logger: logger)

        _ = AppDependencies.makeWithSwiftData(
            modelPartition: .current,
            syncEnablementPolicy: .current,
            syncCoordinator: syncCoordinator,
            syncBootstrapPreferenceStore: AppDependenciesFixedSyncBootstrapPreferenceStore(currentPreference: .disabled),
            logger: logger
        )

        #expect(logger.contains("Starting model container setup"))
        #expect(logger.contains("syncBackedStoreIdentifier=SyncBackedStore"))
        #expect(logger.contains("Model container setup succeeded"))
    }
}
