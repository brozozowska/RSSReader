import SwiftUI

struct ContentView: View {
    var body: some View {
        AppComposition.makeRoot(modelPartition: AppComposition.persistenceModelPartition)
    }
}

#Preview {
    ContentView()
}
