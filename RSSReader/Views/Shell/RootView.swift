import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.appDependencies) private var dependencies
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar
    @State private var presentedFeedManagementLaunchContext: FeedManagementScreenLaunchContext = .entry
    @State private var interactiveSafariRoute: ArticleSafariRoute?
    @State private var interactiveSafariProgress: CGFloat = 0

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
            set: { selectArticle($0) }
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
                    navigateBackToArticles: {},
                    sourceArticleSafariInteraction: sourceArticleSafariInteraction
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
                    navigateBackToArticles: navigateBackToArticles,
                    sourceArticleSafariInteraction: sourceArticleSafariInteraction
                )
                .id(appState.selectedSidebarSelection)
            }
        }
        .overlay {
            GeometryReader { geometryProxy in
                if let route = currentSafariPresentationRoute {
                    SafariBrowserView(
                        route: route,
                        dismissSafari: dismissPresentedSafari
                    )
                    .background(themeApplicationPolicy.resolvedTheme.primaryBackground.ignoresSafeArea())
                    .offset(x: safariPresentationOffset(containerWidth: geometryProxy.size.width))
                    .allowsHitTesting(appState.presentedSafariRoute != nil)
                    .transition(safariPresentationTransition)
                    .zIndex(1)
                }
            }
        }
        .animation(safariPresentationAnimation, value: appState.presentedSafariRoute)
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
                    launchContext: feedManagementLaunchContextForPresentation
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
        .onChange(of: appState.isPresentingFeedManagementScreen) { _, isPresenting in
            if isPresenting {
                presentedFeedManagementLaunchContext = appState.feedManagementLaunchContext
            }
        }
        .onChange(of: appState.feedManagementLaunchContext) { _, launchContext in
            if appState.isPresentingFeedManagementScreen {
                presentedFeedManagementLaunchContext = launchContext
            }
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
                    presentedFeedManagementLaunchContext = appState.feedManagementLaunchContext
                    appState.presentFeedManagementScreen()
                } else {
                    appState.dismissFeedManagementScreen()
                }
            }
        )
    }

    private var feedManagementLaunchContextForPresentation: FeedManagementScreenLaunchContext {
        if appState.isPresentingFeedManagementScreen {
            return appState.feedManagementLaunchContext
        }

        return presentedFeedManagementLaunchContext
    }

    private var safariPresentationTransition: AnyTransition {
        .move(edge: .trailing)
    }

    private var currentSafariPresentationRoute: ArticleSafariRoute? {
        appState.presentedSafariRoute ?? interactiveSafariRoute
    }

    private var safariPresentationAnimation: Animation {
        ReadingShellTransitionAnimation.screen
    }

    private var sourceArticleSafariInteraction: ReaderSourceArticleSafariInteractionHandlers {
        ReaderSourceArticleSafariInteractionHandlers(
            update: updateInteractiveSafariPresentation,
            cancel: cancelInteractiveSafariPresentation,
            finish: finishInteractiveSafariPresentation
        )
    }

    private func dismissPresentedSafari() {
        withAnimation(safariPresentationAnimation) {
            appState.dismissPresentedSafari()
        }
    }

    private func updateInteractiveSafariPresentation(route: ArticleSafariRoute, progress: CGFloat) {
        guard appState.presentedSafariRoute == nil else { return }
        interactiveSafariRoute = route
        interactiveSafariProgress = min(max(progress, 0), 1)
    }

    private func cancelInteractiveSafariPresentation() {
        guard interactiveSafariRoute != nil else { return }
        withAnimation(safariPresentationAnimation) {
            interactiveSafariProgress = 0
            interactiveSafariRoute = nil
        }
    }

    private func finishInteractiveSafariPresentation() {
        withAnimation(safariPresentationAnimation) {
            interactiveSafariProgress = 1
            interactiveSafariRoute = nil
        }
    }

    private func safariPresentationOffset(containerWidth: CGFloat) -> CGFloat {
        guard appState.presentedSafariRoute == nil else { return 0 }
        guard interactiveSafariRoute != nil else { return 0 }

        let hiddenOffset = containerWidth * (1 - interactiveSafariProgress)
        switch layoutDirection {
        case .leftToRight:
            return hiddenOffset
        case .rightToLeft:
            return -hiddenOffset
        @unknown default:
            return hiddenOffset
        }
    }

    private func selectArticle(_ articleID: UUID?) {
        withAnimation(ReadingShellTransitionAnimation.screen) {
            dependencies.appActions.selectArticle(id: articleID, using: appState)
            syncPreferredCompactColumn()
        }
    }

    private func navigateBackToArticles() {
        withAnimation(ReadingShellTransitionAnimation.screen) {
            appState.selectedArticleID = nil
            syncPreferredCompactColumn()
        }
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
