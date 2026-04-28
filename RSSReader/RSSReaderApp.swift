import SwiftUI

@main
struct RSSReaderApp: App {
    private let dependencies: AppDependencies

    @MainActor
    init() {
#if DEBUG
        let logger: Logging = FilteredLogger(
            minLevel: .debug,
            base: OSLogger(category: "sync")
        )
        CloudKitDevelopmentSchemaBootstrap.bootstrapIfNeeded(logger: logger)
#endif
        let syncCoordinator = SyncCoordinator()
        self.dependencies = AppDependencies.makeWithSwiftData(
            modelPartition: AppComposition.persistenceModelPartition,
            syncEnablementPolicy: AppComposition.syncEnablementPolicy,
            syncCoordinator: syncCoordinator
        )
        self.dependencies.startSyncCoordinatorAppLifetime()
    }

    var body: some Scene {
        WindowGroup {
            AppComposition.makeRoot(dependencies: dependencies)
        }
    }
}
