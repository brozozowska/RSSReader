import SwiftUI

@MainActor
func performBackgroundAppRefresh(using dependencies: AppDependencies) async -> BackgroundRefreshExecutionOutcome {
    let executionCoordinator = DefaultBackgroundRefreshExecutionCoordinator(dependencies: dependencies)
    return await executionCoordinator.executeAppRefresh()
}

@MainActor
func logBackgroundRefreshRegistration(
    using logger: Logging,
    identifier: String = BackgroundRefreshTaskConfiguration.appRefreshIdentifier
) {
    logger.info(
        "Configured background refresh app task registration identifier=\(identifier) handler=SwiftUI.backgroundTask(.appRefresh)"
    )
}

@main
struct RSSReaderApp: App {
    static let backgroundAppRefreshIdentifier = BackgroundRefreshTaskConfiguration.appRefreshIdentifier

    private let dependencies: AppDependencies

    @MainActor
    init() {
        let dependencies = AppComposition.makeAppDependencies()
        self.dependencies = dependencies
        logBackgroundRefreshRegistration(using: dependencies.logger)
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
