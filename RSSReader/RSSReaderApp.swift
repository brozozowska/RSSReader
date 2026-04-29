import SwiftUI

@main
struct RSSReaderApp: App {
    private let dependencies: AppDependencies

    @MainActor
    init() {
        self.dependencies = AppComposition.makeAppDependencies()
    }

    var body: some Scene {
        WindowGroup {
            AppComposition.makeRoot(dependencies: dependencies)
        }
    }
}
