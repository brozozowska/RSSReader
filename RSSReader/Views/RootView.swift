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

enum ReadingShellDetailDestination: Equatable {
    case article(UUID?)
    case webView(ArticleWebViewRoute)
}

enum ReadingShellNavigationState {
    static func detailDestination(
        route: ReadingDetailRoute,
        selectedArticleID: UUID?
    ) -> ReadingShellDetailDestination {
        switch route {
        case .none:
            .article(selectedArticleID)
        case .article(let articleID):
            .article(articleID)
        case .webView(let route):
            .webView(route)
        }
    }
}

struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.appDependencies) private var dependencies
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .content

    var body: some View {
        let detailDestination = ReadingShellNavigationState.detailDestination(
            route: appState.selectedDetailRoute,
            selectedArticleID: appState.selectedArticleID
        )
        let sidebarSelection = Binding<SidebarSelection?>(
            get: { appState.selectedSidebarSelection },
            set: { appState.selectReadingSource($0) }
        )
        let articleSelection = Binding<UUID?>(
            get: { appState.selectedArticleID },
            set: { dependencies.selectArticle(id: $0, using: appState) }
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
            switch detailDestination {
            case .article(let articleID):
                ReaderView(
                    articleID: articleID,
                    showsBackButton: ArticleScreenNavigationState.showsBackButton(
                        horizontalSizeClass: horizontalSizeClass,
                        articleSelection: articleID
                    ),
                    navigateBackToArticles: { appState.selectedArticleID = nil }
                )
            case .webView(let route):
                WebViewScreenView(
                    route: route,
                    closeWebView: { appState.dismissPresentedWebView() }
                )
            }
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
