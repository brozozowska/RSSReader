import SwiftUI

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
            await handleBackgroundAppRefresh()
        }
    }

    @MainActor
    private func handleBackgroundAppRefresh() async {
        _ = await dependencies.refreshFeedsForBackground()
    }
}
