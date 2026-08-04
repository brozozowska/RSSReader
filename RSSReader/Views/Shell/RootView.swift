import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.appDependencies) private var dependencies
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var presentedFeedManagementLaunchContext: FeedManagementScreenLaunchContext = .entry
    @State private var interactiveSafariRoute: ArticleSafariRoute?
    @State private var interactiveSafariProgress: CGFloat = 0
    @State private var interactiveSafariDismissalRoute: ArticleSafariRoute?
    @State private var interactiveSafariDismissalProgress: CGFloat = 0
    @State private var articlesScreenController = ArticlesScreenController()

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
            get: { appState.presentedSidebarSelection },
            set: { prepareAndPresentSidebarSelection($0) }
        )
        let articleSelection = Binding<UUID?>(
            get: { appState.selectedArticleID },
            set: { selectArticle($0) }
        )

        NavigationSplitView {
            SidebarView(selection: sidebarSelection)
        } content: {
            ArticleListView(
                selectedSidebarSelection: appState.selectedSidebarSelection,
                selectedSidebarArticleFilter: appState.selectedSidebarArticleFilter,
                reloadID: appState.articleListReloadID,
                controller: articlesScreenController,
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
                        dismissSafari: dismissPresentedSafari,
                        backNavigationInteraction: safariBackNavigationInteraction
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

    @MainActor
    private func prepareAndPresentSidebarSelection(_ selection: SidebarSelection?) {
        guard let selection else {
            if horizontalSizeClass == .compact {
                articlesScreenController.endPresentation()
            }
            appState.updatePresentedSidebarSelection(nil)
            return
        }

        let sidebarArticleFilter = appState.selectedSidebarArticleFilter
        let presentationLoadTask = articlesScreenController.prepareForPresentation(
            selection: selection,
            sidebarArticleFilter: sidebarArticleFilter,
            dependencies: dependencies
        )
        appState.updatePresentedSidebarSelection(selection)
        guard let presentationLoadTask else { return }

        Task { @MainActor in
            await presentationLoadTask.value
            guard appState.selectedSidebarSelection == selection,
                  appState.selectedSidebarArticleFilter == sidebarArticleFilter else {
                return
            }

            appState.updateArticleNavigationContext(
                articlesScreenController.visibleArticleIDs(),
                sidebarSelection: selection,
                sidebarArticleFilter: sidebarArticleFilter,
                articleListSessionID: articlesScreenController.currentArticleListSessionID
            )
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
        appState.presentedSafariRoute
            ?? interactiveSafariDismissalRoute
            ?? interactiveSafariRoute
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

    private var safariBackNavigationInteraction: SafariBrowserBackNavigationInteractionHandlers {
        SafariBrowserBackNavigationInteractionHandlers(
            update: updateInteractiveSafariDismissal,
            cancel: cancelInteractiveSafariDismissal,
            finish: finishInteractiveSafariDismissal
        )
    }

    private func dismissPresentedSafari() {
        interactiveSafariDismissalProgress = 0
        withAnimation(safariPresentationAnimation) {
            appState.dismissPresentedSafari()
        }
    }

    private func updateInteractiveSafariDismissal(progress: CGFloat) {
        guard isPresentingDirectArticleSafari else { return }
        interactiveSafariDismissalProgress = min(max(progress, 0), 1)
    }

    private func cancelInteractiveSafariDismissal() {
        guard isPresentingDirectArticleSafari else { return }
        withAnimation(safariPresentationAnimation) {
            interactiveSafariDismissalProgress = 0
        }
    }

    private func finishInteractiveSafariDismissal() {
        guard case .safari(let route, dismissalTarget: .articleList) = appState.selectedDetailRoute else {
            dismissPresentedSafari()
            return
        }

        interactiveSafariDismissalRoute = route
        appState.dismissPresentedSafari()
        withAnimation(
            safariPresentationAnimation,
            completionCriteria: .logicallyComplete
        ) {
            interactiveSafariDismissalProgress = 1
        } completion: {
            interactiveSafariDismissalRoute = nil
            interactiveSafariDismissalProgress = 0
        }
    }

    private var isPresentingDirectArticleSafari: Bool {
        guard case .safari(_, dismissalTarget: .articleList) = appState.selectedDetailRoute else {
            return false
        }
        return true
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
        if appState.presentedSafariRoute != nil || interactiveSafariDismissalRoute != nil {
            let visibleOffset = containerWidth * interactiveSafariDismissalProgress
            switch layoutDirection {
            case .leftToRight:
                return visibleOffset
            case .rightToLeft:
                return -visibleOffset
            @unknown default:
                return visibleOffset
            }
        }

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
        }
    }

    private func navigateBackToArticles() {
        withAnimation(ReadingShellTransitionAnimation.screen) {
            appState.selectedArticleID = nil
        }
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
