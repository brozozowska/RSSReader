import SwiftUI

struct ReaderView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.appDependencies) private var dependencies
    @Environment(\.appThemeVariant) private var appThemeVariant
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    let articleID: UUID?
    let reloadID: UUID
    let sourceArticleSafariInteraction: ReaderSourceArticleSafariInteractionHandlers
    let canLoadNextArticleContinuation: Bool
    let loadArticleContinuation: @MainActor (ReaderAdjacentArticleNavigationDirection) async -> UUID?
    let prefetchArticleContinuation: @MainActor (Int) async -> Void
    let articleNavigationHandler: @MainActor (UUID, ReaderAdjacentArticleNavigationDirection, ArticleListSessionReference?) -> Void
    let previewScreenState: ArticleScreenState?
    let articleStateMutationHandler: @MainActor (UUID, ArticleUserStateSnapshot, ArticleListSessionReference) -> Void
    @State private var controller = ArticleScreenController()
    @State private var adjacentNavigationControlsMode: ReaderAdjacentNavigationControlsMode = .swipesAndToolbarControls
    @State private var navigation = ReaderArticleNavigationCoordinator()
    @State private var interactionContainerWidth: CGFloat = 0

    init(
        articleID: UUID?,
        reloadID: UUID = UUID(),
        sourceArticleSafariInteraction: ReaderSourceArticleSafariInteractionHandlers = .inactive,
        canLoadNextArticleContinuation: Bool = false,
        loadArticleContinuation: @escaping @MainActor (ReaderAdjacentArticleNavigationDirection) async -> UUID? = { _ in nil },
        prefetchArticleContinuation: @escaping @MainActor (Int) async -> Void = { _ in },
        articleNavigationHandler: @escaping @MainActor (UUID, ReaderAdjacentArticleNavigationDirection, ArticleListSessionReference?) -> Void = { _, _, _ in },
        previewScreenState: ArticleScreenState? = nil,
        articleStateMutationHandler: @escaping @MainActor (UUID, ArticleUserStateSnapshot, ArticleListSessionReference) -> Void = { _, _, _ in }
    ) {
        self.articleID = articleID
        self.reloadID = reloadID
        self.sourceArticleSafariInteraction = sourceArticleSafariInteraction
        self.canLoadNextArticleContinuation = canLoadNextArticleContinuation
        self.loadArticleContinuation = loadArticleContinuation
        self.prefetchArticleContinuation = prefetchArticleContinuation
        self.articleNavigationHandler = articleNavigationHandler
        self.previewScreenState = previewScreenState
        self.articleStateMutationHandler = articleStateMutationHandler
        self._controller = State(initialValue: ArticleScreenController(previewScreenState: previewScreenState))
    }

    var body: some View {
        let currentArticleID = resolvedArticleID
        let adjacentTransitionContext = navigation.activeTransition(
            targetArticleID: currentArticleID
        )
        let preservesStaleContent = adjacentTransitionContext != nil
        let viewState = controller.screenState.derivedViewState(
            selectedArticleID: currentArticleID,
            preservesStaleContent: preservesStaleContent,
            preservedStaleArticleID: adjacentTransitionContext?.sourceArticleID
        )
        let contentTransitionID = viewState.content?.articleID ?? currentArticleID
        let chromeUnderlayEdges: Edge.Set = viewState.content == nil ? [] : [.top, .bottom]

        GeometryReader { geometryProxy in
            ZStack {
                ReaderArticleContentSurface(
                    viewState: viewState,
                    contentSafeAreaInsets: geometryProxy.safeAreaInsets,
                    actionHandlers: actionHandlers,
                    onScrollGeometryChange: updateOverscroll,
                    onScrollPhaseChange: updateScrollPhase
                )
                .background(appThemeVariant.primaryBackground)
                .id(contentTransitionID)
                .transition(navigation.articleTransition(reduceMotion: reduceMotion))
            }
            .overlay(alignment: .top) {
                ReaderAdjacentArticleOverscrollIndicator(
                    systemImage: "chevron.up",
                    progress: navigation.overscrollState.previousProgress,
                    isReady: navigation.overscrollState.previousProgress >= 1
                )
                .padding(
                    .top,
                    geometryProxy.safeAreaInsets.top + ReaderChromeUnderlayLayout.indicatorChromeSpacing
                )
            }
            .overlay(alignment: .bottom) {
                ReaderAdjacentArticleOverscrollIndicator(
                    systemImage: "chevron.down",
                    progress: navigation.overscrollState.nextProgress,
                    isReady: navigation.overscrollState.nextProgress >= 1
                )
                .padding(
                    .bottom,
                    geometryProxy.safeAreaInsets.bottom + ReaderChromeUnderlayLayout.indicatorChromeSpacing
                )
            }
            .clipped()
            .ignoresSafeArea(.container, edges: chromeUnderlayEdges)
        }
        .animation(navigation.animation(reduceMotion: reduceMotion), value: contentTransitionID)
        .sensoryFeedback(
            .impact(flexibility: .solid, intensity: 0.75),
            trigger: navigation.readyHapticTrigger
        )
        .background(appThemeVariant.primaryBackground.ignoresSafeArea())
        .toolbarTitleDisplayMode(.inline)
        .navigationTitle(Text(verbatim: ""))
        .toolbar {
            ReaderArticleToolbarContent(
                toolbarActions: viewState.toolbarActions,
                adjacentNavigationControlsMode: adjacentNavigationControlsMode,
                previousArticleID: appState.adjacentArticleID(.previous),
                canNavigateToNextArticle: canNavigateToNextArticle,
                actionHandlers: actionHandlers,
                onPreviousArticleTap: { navigation.navigate(.previous, context: navigationContext) },
                onNextArticleTap: { navigation.navigate(.next, context: navigationContext) }
            )
        }
        .task(id: ArticleScreenLoadContext(articleID: currentArticleID, reloadID: reloadID)) {
            guard previewScreenState == nil else { return }
            loadReaderAdjacentNavigationControlsMode()
            await navigation.load(
                articleID: currentArticleID,
                transition: adjacentTransitionContext,
                context: navigationContext
            )
        }
        .task(id: adjacentImagePrefetchContext, priority: .utility) {
            updateAdjacentImagePrefetchWindow()
        }
        .task(id: articleContinuationPrefetchContext, priority: .utility) {
            guard let articleContinuationPrefetchContext else { return }
            await prefetchArticleContinuation(
                articleContinuationPrefetchContext.minimumNextArticleCount
            )
        }
        .onChange(of: appState.isPresentingSettingsScreen) { _, isPresentingSettingsScreen in
            guard previewScreenState == nil, isPresentingSettingsScreen == false else { return }
            loadReaderAdjacentNavigationControlsMode()
        }
        .modifier(ReaderSourceArticleGestureModifier(
            containerWidth: $interactionContainerWidth,
            interaction: sourceArticleSafariInteraction,
            openingRequest: { controller.sourceArticleOpeningRequest(dependencies: dependencies) },
            openSourceArticle: actionHandlers.openSourceArticle
        ))
        .onDisappear { navigation.cancelPendingTasks() }
    }

    private var resolvedArticleID: UUID? {
        previewScreenState == nil ? appState.selectedArticleID : articleID
    }

    private var adjacentImagePrefetchContext: ReaderAdjacentArticleImagePrefetchContext? {
        guard previewScreenState == nil,
              let currentArticleID = resolvedArticleID,
              let articleListSession = appState.currentArticleListSessionReference,
              interactionContainerWidth.isFinite,
              displayScale.isFinite else {
            return nil
        }

        let contentWidth = interactionContainerWidth - (ReaderChromeUnderlayLayout.contentMargin * 2)
        guard contentWidth > 0, displayScale > 0 else { return nil }

        let previousCandidateArticleIDs = appState.adjacentArticleIDs(
            .previous,
            limit: ReaderAdjacentArticleImagePrefetchPolicy.maximumCandidateArticleCountPerDirection
        )
        let nextCandidateArticleIDs = appState.adjacentArticleIDs(
            .next,
            limit: ReaderAdjacentArticleImagePrefetchPolicy.maximumCandidateArticleCountPerDirection
        )
        guard previousCandidateArticleIDs.isEmpty == false
                || nextCandidateArticleIDs.isEmpty == false else {
            return nil
        }

        return ReaderAdjacentArticleImagePrefetchContext(
            currentArticleID: currentArticleID,
            articleListSessionID: articleListSession.id,
            previousCandidateArticleIDs: previousCandidateArticleIDs,
            nextCandidateArticleIDs: nextCandidateArticleIDs,
            displayTarget: ArticleImageDisplayTarget(
                displayWidth: Double(contentWidth),
                displayScale: Double(displayScale)
            )
        )
    }

    private var articleContinuationPrefetchContext: ReaderArticleContinuationPrefetchContext? {
        guard previewScreenState == nil,
              canLoadNextArticleContinuation,
              let currentArticleID = resolvedArticleID,
              let articleListSession = appState.currentArticleListSessionReference else {
            return nil
        }

        let minimumNextArticleCount =
            ReaderAdjacentArticleImagePrefetchPolicy.maximumCandidateArticleCountPerDirection
        let materializedNextArticleCount = appState.adjacentArticleIDs(
            .next,
            limit: minimumNextArticleCount
        ).count
        guard materializedNextArticleCount < minimumNextArticleCount else { return nil }

        return ReaderArticleContinuationPrefetchContext(
            currentArticleID: currentArticleID,
            articleListSessionID: articleListSession.id,
            minimumNextArticleCount: minimumNextArticleCount
        )
    }

    private func loadReaderAdjacentNavigationControlsMode() {
        guard let appSettingsService = dependencies.appSettingsService else {
            adjacentNavigationControlsMode = .swipesAndToolbarControls
            return
        }

        do {
            adjacentNavigationControlsMode = try appSettingsService.fetchSettings().readerAdjacentNavigationControlsMode
        } catch {
            dependencies.logger.error("Failed to load reader adjacent navigation controls mode: \(error)")
            adjacentNavigationControlsMode = .swipesAndToolbarControls
        }
    }

    private func updateOverscroll(_ geometry: ReaderArticleScrollGeometry) {
        navigation.updateOverscroll(
            geometry,
            isEnabled: previewScreenState == nil && adjacentNavigationControlsMode.allowsAdjacentArticleSwipes,
            hasPrevious: appState.adjacentArticleID(.previous) != nil,
            hasNext: canNavigateToNextArticle
        )
    }

    private func updateScrollPhase(oldPhase: ScrollPhase, newPhase: ScrollPhase) {
        if let direction = navigation.updateScrollPhase(
            oldPhase: oldPhase,
            newPhase: newPhase,
            isEnabled: previewScreenState == nil && adjacentNavigationControlsMode.allowsAdjacentArticleSwipes
        ) {
            navigation.navigate(direction, context: navigationContext)
        }
    }

    private var canNavigateToNextArticle: Bool {
        appState.adjacentArticleID(.next) != nil
            || (canLoadNextArticleContinuation && navigation.isLoadingContinuation == false)
    }

    private var navigationContext: ReaderArticleNavigationContext {
        ReaderArticleNavigationContext(
            appState: appState,
            controller: controller,
            dependencies: dependencies,
            canLoadContinuation: canLoadNextArticleContinuation,
            loadContinuation: { direction in await loadArticleContinuation(direction) },
            didNavigate: { articleID, direction, session in
                articleNavigationHandler(articleID, direction, session)
            },
            readOnOpen: articleReadOnOpenHandler(for: appState.currentArticleListSessionReference),
            updateImagePrefetch: updateAdjacentImagePrefetchWindow
        )
    }

    private func updateAdjacentImagePrefetchWindow() {
        dependencies.articleImageRuntime.prefetchCoordinator.update(
            context: adjacentImagePrefetchContext,
            articleQueryService: dependencies.articleQueryService
        )
    }

    @MainActor
    private func articleReadOnOpenHandler(
        for listSession: ArticleListSessionReference?
    ) -> ArticleReadOnOpenHandler? {
        guard let listSession else { return nil }

        return { articleID, persistedState in
            articleStateMutationHandler(articleID, persistedState, listSession)
        }
    }

    private var actionHandlers: ArticleScreenActionHandlers {
        ArticleScreenActionHandlers(
            toggleReadStatus: {
                let listSession = appState.currentArticleListSessionReference
                controller.toggleArticleReadStatus(
                    dependencies: dependencies,
                    isPreviewMode: previewScreenState != nil,
                    articleStateMutationHandler: { articleID, persistedState in
                        guard let listSession else { return }
                        articleStateMutationHandler(articleID, persistedState, listSession)
                    }
                )
            },
            toggleStarredStatus: {
                let listSession = appState.currentArticleListSessionReference
                controller.toggleArticleStarredStatus(
                    dependencies: dependencies,
                    isPreviewMode: previewScreenState != nil,
                    articleStateMutationHandler: { articleID, persistedState in
                        guard let listSession else { return }
                        articleStateMutationHandler(articleID, persistedState, listSession)
                    }
                )
            },
            openSourceArticle: {
                _controller.wrappedValue.openSourceArticle(
                    dependencies: dependencies,
                    appState: appState,
                    openExternalURL: { externalURL in
                        openURL(externalURL)
                    }
                )
            },
            bodyLinkTapped: { url in
                _controller.wrappedValue.handleBodyLinkTap(
                    url,
                    dependencies: dependencies,
                    appState: appState,
                    openExternalURL: { externalURL in
                        openURL(externalURL)
                    }
                )
            }
        )
    }
}

private struct ArticleScreenLoadContext: Hashable {
    let articleID: UUID?
    let reloadID: UUID
}

private struct ReaderArticleContinuationPrefetchContext: Hashable {
    let currentArticleID: UUID
    let articleListSessionID: UUID
    let minimumNextArticleCount: Int
}

struct ReaderSourceArticleSafariInteractionHandlers {
    let update: (ArticleSafariRoute, CGFloat) -> Void
    let cancel: () -> Void
    let finish: () -> Void

    static let inactive = ReaderSourceArticleSafariInteractionHandlers(
        update: { _, _ in },
        cancel: {},
        finish: {}
    )
}
