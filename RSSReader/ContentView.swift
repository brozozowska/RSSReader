import SwiftUI

struct ContentView: View {
    var body: some View {
        AppComposition.makeRoot(models: AppComposition.appModels)
    }
}

#Preview {
    ContentView()
}
