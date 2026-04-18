import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.appDependencies) private var dependencies
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar

    var body: some View {
        let detailDestination = ReadingShellDetailNavigationState.detailDestination(
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
                showsBackButton: ReadingShellCompactNavigationState.showsArticlesBackButton(
                    horizontalSizeClass: horizontalSizeClass,
                    sourceSelection: appState.selectedSidebarSelection
                ),
                navigateBackToSources: { preferredCompactColumn = .sidebar },
                previewScreenState: nil,
                selection: articleSelection
            )
        } detail: {
            switch detailDestination {
            case .none:
                if horizontalSizeClass == .compact {
                    EmptyView()
                } else {
                    ReaderView(
                        articleID: nil,
                        showsBackButton: false,
                        navigateBackToArticles: {}
                    )
                }
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
        .sheet(isPresented: settingsPresentationBinding) {
            SettingsScreenView(
                dismiss: { dependencies.dismissSettings(using: appState) }
            )
        }
        .onAppear(perform: syncPreferredCompactColumn)
        .onChange(of: appState.selectedSidebarSelection) { _, _ in
            syncPreferredCompactColumn()
        }
        .onChange(of: appState.selectedArticleID) { _, _ in
            syncPreferredCompactColumn()
        }
    }

    private var settingsPresentationBinding: Binding<Bool> {
        Binding(
            get: { appState.isPresentingSettingsScreen },
            set: { isPresented in
                if isPresented {
                    appState.presentSettingsScreen()
                } else {
                    appState.dismissSettingsScreen()
                }
            }
        )
    }

    private func syncPreferredCompactColumn() {
        preferredCompactColumn = ReadingShellCompactNavigationState.preferredCompactColumn(
            sourceSelection: appState.selectedSidebarSelection,
            articleSelection: appState.selectedArticleID
        )
    }
}
