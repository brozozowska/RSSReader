import SwiftUI

@main
struct RSSReaderApp: App {
    static let backgroundAppRefreshIdentifier = BackgroundRefreshTaskConfiguration.appRefreshIdentifier

    private let dependencies: AppDependencies?

    @MainActor
    init() {
#if DEBUG
        let process = ProcessInfo.processInfo
        // Hosted unit tests need the app binary, but own their dependency graphs.
        if !process.arguments.contains("--ui-smoke"),
           process.environment["XCTestSessionIdentifier"] != nil
            || process.environment["XCTestConfigurationFilePath"] != nil {
            dependencies = nil
            return
        }
#endif
        let dependencies = AppComposition.makeAppDependencies()
        self.dependencies = dependencies
        dependencies.reportBackgroundRefreshRegistrationConfigured()
    }

    var body: some Scene {
        WindowGroup {
            if let dependencies {
                AppComposition.makeRoot(dependencies: dependencies)
            } else {
                Color.clear
            }
        }
        .backgroundTask(.appRefresh(Self.backgroundAppRefreshIdentifier)) {
            _ = await dependencies?.executeBackgroundAppRefresh()
        }
    }
}
