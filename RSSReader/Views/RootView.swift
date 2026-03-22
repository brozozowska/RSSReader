import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState
    
    var body: some View {
        Text("RSS Reader")
            .font(.title)
            .padding()
    }
}

struct RootView_Previews: PreviewProvider {
    static var previews: some View {
        RootView()
            .environment(AppState())
    }
}

#Preview {
    RootView()
}
