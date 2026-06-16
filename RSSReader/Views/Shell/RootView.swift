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
            set: { appState.selectSidebarSelection($0) }
        )
        let articleSelection = Binding<UUID?>(
            get: { appState.selectedArticleID },
            set: { dependencies.appActions.selectArticle(id: $0, using: appState) }
        )

        NavigationSplitView(preferredCompactColumn: $preferredCompactColumn) {
            SidebarView(selection: sidebarSelection)
        } content: {
            ArticleListView(
                selectedSidebarSelection: appState.selectedSidebarSelection,
                selectedSidebarArticleFilter: appState.selectedSidebarArticleFilter,
                reloadID: appState.articleListReloadID,
                showsBackButton: ReadingShellCompactNavigationState.showsArticlesBackButton(
                    horizontalSizeClass: horizontalSizeClass,
                    sidebarSelection: appState.selectedSidebarSelection
                ),
                navigateBackToSidebar: { preferredCompactColumn = .sidebar },
                previewScreenState: nil,
                selection: articleSelection
            )
            .id(appState.selectedSidebarSelection)
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
                .id(appState.selectedSidebarSelection)
            }
        }
        .fullScreenCover(isPresented: safariPresentationBinding) {
            if let route = appState.presentedSafariRoute {
                SafariBrowserView(
                    route: route,
                    dismissSafari: { appState.dismissPresentedSafari() }
                )
            }
        }
        .sheet(isPresented: settingsPresentationBinding) {
            AppThemePresentationScope(
                interfaceThemeMode: appState.interfaceThemeMode,
                systemColorScheme: systemColorScheme
            ) {
                SettingsScreenView(
                    dismiss: { dependencies.appActions.dismissSettings(using: appState) }
                )
            }
        }
        .sheet(isPresented: feedManagementPresentationBinding) {
            AppThemePresentationScope(
                interfaceThemeMode: appState.interfaceThemeMode,
                systemColorScheme: systemColorScheme
            ) {
                FeedManagementScreenView(
                    dismiss: { dependencies.appActions.dismissFeedManagement(using: appState) },
                    launchContext: appState.feedManagementLaunchContext
                )
            }
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

    private var feedManagementPresentationBinding: Binding<Bool> {
        Binding(
            get: { appState.isPresentingFeedManagementScreen },
            set: { isPresented in
                if isPresented {
                    appState.presentFeedManagementScreen()
                } else {
                    appState.dismissFeedManagementScreen()
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
            sidebarSelection: appState.selectedSidebarSelection,
            articleSelection: appState.selectedArticleID
        )
    }
}

private struct AppThemePresentationScope<Content: View>: View {
    let interfaceThemeMode: InterfaceThemeMode
    let systemColorScheme: ColorScheme
    @ViewBuilder let content: () -> Content

    var body: some View {
        let themeApplicationPolicy = AppThemeApplicationPolicy(
            interfaceThemeMode: interfaceThemeMode,
            systemColorScheme: systemColorScheme
        )

        content()
            .preferredColorScheme(themeApplicationPolicy.preferredColorScheme)
            .environment(\.colorScheme, themeApplicationPolicy.resolvedColorScheme)
            .environment(\.appThemeVariant, themeApplicationPolicy.resolvedTheme)
            .background(themeApplicationPolicy.resolvedTheme.primaryBackground.ignoresSafeArea())
    }
}
