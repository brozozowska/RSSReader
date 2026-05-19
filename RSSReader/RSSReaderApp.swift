import SwiftUI

@main
struct RSSReaderApp: App {
    static let backgroundAppRefreshIdentifier = BackgroundRefreshTaskConfiguration.appRefreshIdentifier

    private let dependencies: AppDependencies

    @MainActor
    init() {
        AppComposition.configureSharedURLCache()

        let dependencies = AppComposition.makeAppDependencies()
        self.dependencies = dependencies
        dependencies.reportBackgroundRefreshRegistrationConfigured()
    }

    var body: some Scene {
        WindowGroup {
            AppComposition.makeRoot(dependencies: dependencies)
        }
        .backgroundTask(.appRefresh(Self.backgroundAppRefreshIdentifier)) {
            _ = await dependencies.executeBackgroundAppRefresh()
        }
    }
}
