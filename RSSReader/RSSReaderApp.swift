import SwiftUI

@MainActor
func performBackgroundAppRefresh(using dependencies: AppDependencies) async -> BackgroundRefreshExecutionOutcome {
    let executionCoordinator = DefaultBackgroundRefreshExecutionCoordinator(dependencies: dependencies)
    return await executionCoordinator.executeAppRefresh()
}

@MainActor
func reportBackgroundRefreshRegistration(
    using dependencies: AppDependencies,
    identifier: String = BackgroundRefreshTaskConfiguration.appRefreshIdentifier
) {
    dependencies.backgroundRefreshValidationDiagnosticsReporter.reportRegistrationConfigured(
        identifier: identifier,
        handlerDescription: "SwiftUI.backgroundTask(.appRefresh)"
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
        reportBackgroundRefreshRegistration(using: dependencies)
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
