import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let feedSelection = Binding<UUID?>(
            get: { appState.selectedFeedID },
            set: { appState.selectedFeedID = $0 }
        )
        let articleSelection = Binding<UUID?>(
            get: { appState.selectedArticleID },
            set: { appState.selectedArticleID = $0 }
        )

        NavigationSplitView {
            SidebarView(selection: feedSelection)
        } content: {
            ArticleListView(selectedFeedID: appState.selectedFeedID, selection: articleSelection)
        } detail: {
            ReaderView(articleID: appState.selectedArticleID)
        }
    }
}

#Preview {
    RootView()
        .environment(AppState())
}
