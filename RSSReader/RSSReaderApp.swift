import SwiftUI

@main
struct RSSReaderApp: App {
    var body: some Scene {
        WindowGroup {
            AppComposition.makeRoot(modelPartition: AppComposition.persistenceModelPartition)
        }
    }
}
