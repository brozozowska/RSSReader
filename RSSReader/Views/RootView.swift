import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let sidebarSelection = Binding<SidebarSelection?>(
            get: { appState.selectedSidebarSelection },
            set: { appState.selectedSidebarSelection = $0 }
        )
        let articleSelection = Binding<UUID?>(
            get: { appState.selectedArticleID },
            set: { appState.selectedArticleID = $0 }
        )

        NavigationSplitView {
            SidebarView(selection: sidebarSelection)
        } content: {
            ArticleListView(
                selectedSidebarSelection: appState.selectedSidebarSelection,
                selectedFilter: appState.selectedArticleListFilter,
                reloadID: appState.articleListReloadID,
                selection: articleSelection
            )
        } detail: {
            ReaderView(articleID: appState.selectedArticleID)
        }
    }
}

#Preview {
    RootView()
        .environment(AppState())
}
