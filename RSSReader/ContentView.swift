import SwiftUI

// Preview entry point; RSSReaderApp owns the runtime dependency lifetime.
struct ContentView: View {
    var body: some View {
        AppComposition.makeRoot(modelPartition: AppComposition.persistenceModelPartition)
    }
}

#Preview {
    ContentView()
}
