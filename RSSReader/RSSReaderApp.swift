import SwiftUI

@main
struct RSSReaderApp: App {
    init() {
#if DEBUG
        let logger: Logging = FilteredLogger(
            minLevel: .debug,
            base: OSLogger(category: "sync")
        )
        CloudKitDevelopmentSchemaBootstrap.bootstrapIfNeeded(logger: logger)
#endif
    }

    var body: some Scene {
        WindowGroup {
            AppComposition.makeRoot(modelPartition: AppComposition.persistenceModelPartition)
        }
    }
}
