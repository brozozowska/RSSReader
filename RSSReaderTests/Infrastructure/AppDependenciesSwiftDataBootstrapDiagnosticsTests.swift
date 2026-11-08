import Testing
@testable import RSSReader

@Suite("Infrastructure / AppDependencies / SwiftData Bootstrap Diagnostics")
@MainActor
struct AppDependenciesSwiftDataBootstrapDiagnosticsTests {
    @Test
    func appDependenciesMakeWithSwiftDataLogsModelContainerSetupMarkers() {
        let logger = RecordingLogger()
        _ = makeIsolatedSwiftDataBootstrap(logger: logger)

        #expect(logger.contains("Starting model container setup"))
        #expect(logger.contains("syncBackedStoreIdentifier=SyncBackedStore"))
        #expect(logger.contains("syncBackedStoreURL=in-memory"))
        #expect(logger.contains("Model container setup succeeded"))
    }
}
