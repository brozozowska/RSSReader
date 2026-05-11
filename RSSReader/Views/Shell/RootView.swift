import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.appDependencies) private var dependencies
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar

    var body: some View {
        let themeApplicationPolicy = AppThemeApplicationPolicy(
            interfaceThemeMode: appState.interfaceThemeMode,
            systemColorScheme: systemColorScheme
        )
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
                    reloadID: appState.articleScreenReloadID,
                    showsBackButton: false,
                    navigateBackToArticles: {}
                )
                }
            case .article(let articleID):
                ReaderView(
                    articleID: articleID,
                    reloadID: appState.articleScreenReloadID,
                    showsBackButton: ArticleScreenNavigationState.showsBackButton(
                        horizontalSizeClass: horizontalSizeClass,
                        articleSelection: articleID
                    ),
                    navigateBackToArticles: { appState.selectedArticleID = nil }
                )
            }
        }
        .fullScreenCover(isPresented: safariPresentationBinding) {
            if let route = appState.presentedSafariRoute {
                WebViewScreenView(
                    route: route,
                    closeWebView: { appState.dismissPresentedSafari() }
                )
            }
        }
        .sheet(isPresented: settingsPresentationBinding) {
            SettingsScreenView(
                dismiss: { dependencies.dismissSettings(using: appState) }
            )
        }
        .sheet(isPresented: sourceManagementPresentationBinding) {
            SourceManagementScreenView(
                dismiss: { dependencies.dismissSourceManagement(using: appState) },
                launchContext: appState.sourceManagementLaunchContext
            )
        }
        .preferredColorScheme(themeApplicationPolicy.preferredColorScheme)
        .environment(\.appThemeVariant, themeApplicationPolicy.resolvedTheme)
        .background(themeApplicationPolicy.resolvedTheme.primaryBackground.ignoresSafeArea())
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

    private var sourceManagementPresentationBinding: Binding<Bool> {
        Binding(
            get: { appState.isPresentingSourceManagementScreen },
            set: { isPresented in
                if isPresented {
                    appState.presentSourceManagementScreen()
                } else {
                    appState.dismissSourceManagementScreen()
                }
            }
        )
    }

    private var safariPresentationBinding: Binding<Bool> {
        Binding(
            get: { appState.presentedSafariRoute != nil },
            set: { isPresented in
                if isPresented == false {
                    appState.dismissPresentedSafari()
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
