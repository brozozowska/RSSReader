import SwiftUI

@MainActor
func performBackgroundAppRefresh(using dependencies: AppDependencies) async -> BackgroundRefreshExecutionOutcome {
    let executionCoordinator = DefaultBackgroundRefreshExecutionCoordinator(dependencies: dependencies)
    return await executionCoordinator.executeAppRefresh()
}

@main
struct RSSReaderApp: App {
    static let backgroundAppRefreshIdentifier = BackgroundRefreshTaskConfiguration.appRefreshIdentifier

    private let dependencies: AppDependencies

    @MainActor
    init() {
        self.dependencies = AppComposition.makeAppDependencies()
    }

    var body: some Scene {
        WindowGroup {
            AppComposition.makeRoot(dependencies: dependencies)
        }
        .backgroundTask(.appRefresh(Self.backgroundAppRefreshIdentifier)) {
            _ = await performBackgroundAppRefresh(using: dependencies)
        }
    }
}
