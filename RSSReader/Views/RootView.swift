import SwiftUI

enum ArticlesScreenNavigationState {
    static func preferredCompactColumn(
        sourceSelection: SidebarSelection?,
        articleSelection: UUID?
    ) -> NavigationSplitViewColumn {
        if articleSelection != nil {
            return .detail
        }

        if sourceSelection != nil {
            return .content
        }

        return .sidebar
    }

    static func showsBackButton(
        horizontalSizeClass: UserInterfaceSizeClass?,
        sourceSelection: SidebarSelection?
    ) -> Bool {
        horizontalSizeClass == .compact && sourceSelection != nil
    }

    static func shouldNavigateBackOnDrag(
        startLocationX: CGFloat,
        translation: CGSize
    ) -> Bool {
        startLocationX <= 32
            && translation.width >= 80
            && abs(translation.height) <= 48
    }
}

struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .content

    var body: some View {
        let sidebarSelection = Binding<SidebarSelection?>(
            get: { appState.selectedSidebarSelection },
            set: { appState.selectReadingSource($0) }
        )
        let articleSelection = Binding<UUID?>(
            get: { appState.selectedArticleID },
            set: { appState.selectedArticleID = $0 }
        )

        NavigationSplitView(preferredCompactColumn: $preferredCompactColumn) {
            SidebarView(selection: sidebarSelection)
        } content: {
            ArticleListView(
                selectedSidebarSelection: appState.selectedSidebarSelection,
                selectedSourcesFilter: appState.selectedSourcesFilter,
                reloadID: appState.articleListReloadID,
                showsBackButton: ArticlesScreenNavigationState.showsBackButton(
                    horizontalSizeClass: horizontalSizeClass,
                    sourceSelection: appState.selectedSidebarSelection
                ),
                navigateBackToSources: { preferredCompactColumn = .sidebar },
                previewScreenState: nil,
                selection: articleSelection
            )
        } detail: {
            ReaderView(articleID: appState.selectedArticleID)
        }
        .onAppear(perform: syncPreferredCompactColumn)
        .onChange(of: appState.selectedSidebarSelection) { _, _ in
            syncPreferredCompactColumn()
        }
        .onChange(of: appState.selectedArticleID) { _, _ in
            syncPreferredCompactColumn()
        }
    }

    private func syncPreferredCompactColumn() {
        preferredCompactColumn = ArticlesScreenNavigationState.preferredCompactColumn(
            sourceSelection: appState.selectedSidebarSelection,
            articleSelection: appState.selectedArticleID
        )
    }
}

#Preview {
    RootView()
        .environment(AppState())
}
