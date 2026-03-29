import SwiftUI

@main
struct RSSReaderApp: App {
    var body: some Scene {
        WindowGroup {
            AppComposition.makeRoot(models: AppComposition.appModels)
        }
    }
}
