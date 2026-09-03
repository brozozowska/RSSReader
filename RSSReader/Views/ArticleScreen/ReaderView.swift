import SwiftUI

struct ReaderView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.appDependencies) private var dependencies
    @Environment(\.appThemeVariant) private var appThemeVariant
    @Environment(\.displayScale) private var displayScale
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.openURL) private var openURL
    let articleID: UUID?
    let reloadID: UUID
    let sourceArticleSafariInteraction: ReaderSourceArticleSafariInteractionHandlers
    let canLoadNextArticleContinuation: Bool
    let loadArticleContinuation: @MainActor (ReaderAdjacentArticleNavigationDirection) async -> UUID?
    let prefetchArticleContinuation: @MainActor (Int) async -> Void
    let previewScreenState: ArticleScreenState?
    @State private var controller = ArticleScreenController()
    @State private var adjacentNavigationControlsMode: ReaderAdjacentNavigationControlsMode = .swipesAndToolbarControls
    @State private var adjacentArticleTransitionContext: AdjacentArticleTransitionContext?
    @State private var adjacentArticleTransitionGeneration = 0
    @State private var pendingAdjacentArticleOverscrollDirection: ReaderAdjacentArticleNavigationDirection?
    @State private var adjacentArticleOverscrollState = ReaderArticleOverscrollNavigationState()
    @State private var adjacentArticleOverscrollReadyHapticTrigger = 0
    @State private var hasTriggeredAdjacentArticleOverscrollReadyHaptic = false
    @State private var isLoadingAdjacentArticleContinuation = false
    @State private var interactionContainerWidth: CGFloat = 0

    init(
        articleID: UUID?,
        reloadID: UUID = UUID(),
        sourceArticleSafariInteraction: ReaderSourceArticleSafariInteractionHandlers = .inactive,
        canLoadNextArticleContinuation: Bool = false,
        loadArticleContinuation: @escaping @MainActor (ReaderAdjacentArticleNavigationDirection) async -> UUID? = { _ in nil },
        prefetchArticleContinuation: @escaping @MainActor (Int) async -> Void = { _ in },
        previewScreenState: ArticleScreenState? = nil
    ) {
        self.articleID = articleID
        self.reloadID = reloadID
        self.sourceArticleSafariInteraction = sourceArticleSafariInteraction
        self.canLoadNextArticleContinuation = canLoadNextArticleContinuation
        self.loadArticleContinuation = loadArticleContinuation
        self.prefetchArticleContinuation = prefetchArticleContinuation
        self.previewScreenState = previewScreenState
        self._controller = State(initialValue: ArticleScreenController(previewScreenState: previewScreenState))
    }

    var body: some View {
        let currentArticleID = resolvedArticleID
        let adjacentTransitionContext = activeAdjacentArticleTransitionContext(
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
                    onScrollGeometryChange: handleArticleScrollGeometryChange,
                    onScrollPhaseChange: handleArticleScrollPhaseChange
                )
                .background(appThemeVariant.primaryBackground)
                .id(contentTransitionID)
                .transition(articleTransition)
            }
            .overlay(alignment: .top) {
                ReaderAdjacentArticleOverscrollIndicator(
                    systemImage: "chevron.up",
                    progress: adjacentArticleOverscrollState.previousProgress,
                    isReady: adjacentArticleOverscrollState.previousProgress >= 1
                )
                .padding(
                    .top,
                    geometryProxy.safeAreaInsets.top + ReaderChromeUnderlayLayout.indicatorChromeSpacing
                )
            }
            .overlay(alignment: .bottom) {
                ReaderAdjacentArticleOverscrollIndicator(
                    systemImage: "chevron.down",
                    progress: adjacentArticleOverscrollState.nextProgress,
                    isReady: adjacentArticleOverscrollState.nextProgress >= 1
                )
                .padding(
                    .bottom,
                    geometryProxy.safeAreaInsets.bottom + ReaderChromeUnderlayLayout.indicatorChromeSpacing
                )
            }
            .clipped()
            .ignoresSafeArea(.container, edges: chromeUnderlayEdges)
        }
        .animation(adjacentArticleAnimation, value: contentTransitionID)
        .sensoryFeedback(
            .impact(flexibility: .solid, intensity: 0.75),
            trigger: adjacentArticleOverscrollReadyHapticTrigger
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
                onPreviousArticleTap: handlePreviousArticleTap,
                onNextArticleTap: handleNextArticleTap
            )
        }
        .task(id: ArticleScreenLoadContext(articleID: currentArticleID, reloadID: reloadID)) {
            guard previewScreenState == nil else { return }
            let adjacentTransitionContext = adjacentTransitionContext
            let readOnOpenHandler = articleReadOnOpenHandler(
                for: appState.currentArticleListSessionReference
            )
            loadReaderAdjacentNavigationControlsMode()
            await controller.load(
                articleID: currentArticleID,
                dependencies: dependencies,
                preservesCurrentArticleDuringLoading: adjacentTransitionContext != nil,
                articleReadOnOpenHandler: readOnOpenHandler
            )
            pendingAdjacentArticleOverscrollDirection = nil
            adjacentArticleOverscrollState = ReaderArticleOverscrollNavigationState()
            await resetAdjacentArticleTransitionDirectionAfterAnimation(
                transitionContext: adjacentTransitionContext
            )
        }
        .task(id: adjacentImagePrefetchContext, priority: .utility) {
            ReaderAdjacentArticleImagePrefetchCoordinator.shared.update(
                context: adjacentImagePrefetchContext,
                articleQueryService: dependencies.articleQueryService
            )
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
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            interactionContainerWidth = newWidth
        }
        .simultaneousGesture(openSourceArticleGesture)
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

    private var articleTransition: AnyTransition {
        switch adjacentArticleTransitionContext?.direction {
        case .next:
            adjacentArticleTransition(insertionEdge: .bottom, removalEdge: .top)
        case .previous:
            adjacentArticleTransition(insertionEdge: .top, removalEdge: .bottom)
        case .none:
            .opacity
        }
    }

    private func adjacentArticleTransition(insertionEdge: Edge, removalEdge: Edge) -> AnyTransition {
        .asymmetric(
            insertion: .move(edge: insertionEdge),
            removal: .move(edge: removalEdge)
        )
    }

    private var adjacentArticleAnimation: Animation {
        .easeInOut(duration: 0.28)
    }

    private func activeAdjacentArticleTransitionContext(
        targetArticleID: UUID?
    ) -> AdjacentArticleTransitionContext? {
        guard let adjacentArticleTransitionContext,
              adjacentArticleTransitionContext.targetArticleID == targetArticleID else {
            return nil
        }

        return adjacentArticleTransitionContext
    }

    private var openSourceArticleGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                handleOpenSourceArticleDragChange(value)
            }
            .onEnded { value in
                handleOpenSourceArticleDragEnd(value)
            }
    }

    private func handleOpenSourceArticleDragChange(_ value: DragGesture.Value) {
        let progress = ArticleScreenNavigationState.openSourceArticleSwipeProgress(
            layoutDirection: layoutDirection,
            containerWidth: interactionContainerWidth,
            translation: value.translation
        )
        guard progress > 0 else {
            sourceArticleSafariInteraction.cancel()
            return
        }

        guard case .inAppBrowser(let route) = controller.sourceArticleOpeningRequest(
            dependencies: dependencies
        ) else {
            return
        }

        sourceArticleSafariInteraction.update(route, progress)
    }

    private func handleOpenSourceArticleDragEnd(_ value: DragGesture.Value) {
        guard ArticleScreenNavigationState.shouldOpenSourceArticleOnDrag(
            layoutDirection: layoutDirection,
            containerWidth: interactionContainerWidth,
            translation: value.translation
        ) else {
            sourceArticleSafariInteraction.cancel()
            return
        }

        actionHandlers.openSourceArticle()
        sourceArticleSafariInteraction.finish()
    }

    private func handleArticleScrollGeometryChange(_ scrollGeometry: ReaderArticleScrollGeometry) {
        guard previewScreenState == nil else { return }
        guard adjacentNavigationControlsMode.allowsAdjacentArticleSwipes else {
            adjacentArticleOverscrollState = ReaderArticleOverscrollNavigationState()
            pendingAdjacentArticleOverscrollDirection = nil
            return
        }

        let overscrollState = ArticleScreenNavigationState.adjacentArticleOverscrollState(
            scrollGeometry: scrollGeometry
        )
        let previousOverscrollState = adjacentArticleOverscrollState
        let newOverscrollState = effectiveAdjacentArticleOverscrollState(overscrollState)

        if ArticleScreenNavigationState.shouldTriggerAdjacentArticleOverscrollReadyHaptic(
            previousState: previousOverscrollState,
            newState: newOverscrollState,
            hasTriggeredInCurrentGesture: hasTriggeredAdjacentArticleOverscrollReadyHaptic
        ) {
            adjacentArticleOverscrollReadyHapticTrigger += 1
            hasTriggeredAdjacentArticleOverscrollReadyHaptic = true
        }

        adjacentArticleOverscrollState = newOverscrollState
        pendingAdjacentArticleOverscrollDirection = adjacentArticleOverscrollState.readyDirection
    }

    private func handleArticleScrollPhaseChange(oldPhase: ScrollPhase, newPhase: ScrollPhase) {
        guard previewScreenState == nil else { return }
        guard adjacentNavigationControlsMode.allowsAdjacentArticleSwipes else {
            pendingAdjacentArticleOverscrollDirection = nil
            adjacentArticleOverscrollState = ReaderArticleOverscrollNavigationState()
            return
        }

        if newPhase == .tracking || newPhase == .interacting {
            pendingAdjacentArticleOverscrollDirection = nil
            adjacentArticleOverscrollState = ReaderArticleOverscrollNavigationState()
            hasTriggeredAdjacentArticleOverscrollReadyHaptic = false
            return
        }

        guard oldPhase == .interacting, newPhase != .interacting else { return }
        guard let direction = pendingAdjacentArticleOverscrollDirection else { return }
        pendingAdjacentArticleOverscrollDirection = nil
        adjacentArticleOverscrollState = ReaderArticleOverscrollNavigationState()
        navigateToAdjacentArticle(direction)
    }

    private func effectiveAdjacentArticleOverscrollState(
        _ overscrollState: ReaderArticleOverscrollNavigationState
    ) -> ReaderArticleOverscrollNavigationState {
        ReaderArticleOverscrollNavigationState(
            previousProgress: appState.adjacentArticleID(.previous) == nil ? 0 : overscrollState.previousProgress,
            nextProgress: canNavigateToNextArticle ? overscrollState.nextProgress : 0
        )
    }

    private func navigateToAdjacentArticle(_ direction: ReaderAdjacentArticleNavigationDirection) {
        guard let sourceArticleID = resolvedArticleID else {
            return
        }

        if let targetArticleID = appState.adjacentArticleID(direction) {
            performAdjacentArticleNavigation(
                direction: direction,
                sourceArticleID: sourceArticleID,
                targetArticleID: targetArticleID
            )
            return
        }

        guard direction == .next,
              canLoadNextArticleContinuation,
              isLoadingAdjacentArticleContinuation == false else {
            return
        }

        isLoadingAdjacentArticleContinuation = true
        Task { @MainActor in
            let targetArticleID = await loadArticleContinuation(direction)
            guard resolvedArticleID == sourceArticleID else {
                isLoadingAdjacentArticleContinuation = false
                return
            }
            isLoadingAdjacentArticleContinuation = false
            guard let targetArticleID else { return }
            performAdjacentArticleNavigation(
                direction: direction,
                sourceArticleID: sourceArticleID,
                targetArticleID: targetArticleID
            )
        }
    }

    private var canNavigateToNextArticle: Bool {
        appState.adjacentArticleID(.next) != nil
            || (canLoadNextArticleContinuation && isLoadingAdjacentArticleContinuation == false)
    }

    private func performAdjacentArticleNavigation(
        direction: ReaderAdjacentArticleNavigationDirection,
        sourceArticleID: UUID,
        targetArticleID: UUID
    ) {
        guard appState.adjacentArticleID(direction) == targetArticleID else { return }

        adjacentArticleTransitionGeneration += 1
        let transitionContext = AdjacentArticleTransitionContext(
            generation: adjacentArticleTransitionGeneration,
            direction: direction,
            sourceArticleID: sourceArticleID,
            targetArticleID: targetArticleID
        )
        adjacentArticleTransitionContext = transitionContext

        let didSelectAdjacentArticle = appState.selectAdjacentArticle(direction)

        if didSelectAdjacentArticle == false {
            clearAdjacentArticleTransitionContext(transitionContext)
            return
        }

        Task {
            await loadCurrentArticleAfterAdjacentNavigationIfNeeded(
                transitionContext: transitionContext
            )
        }
    }

    @MainActor
    private func loadCurrentArticleAfterAdjacentNavigationIfNeeded(
        transitionContext: AdjacentArticleTransitionContext
    ) async {
        do {
            try await Task.sleep(for: .milliseconds(80))
        } catch {
            return
        }
        guard adjacentArticleTransitionContext == transitionContext,
              resolvedArticleID == transitionContext.targetArticleID else {
            return
        }

        guard controller.screenState.article?.id != transitionContext.targetArticleID else {
            await resetAdjacentArticleTransitionDirectionAfterAnimation(
                transitionContext: transitionContext
            )
            return
        }

        let readOnOpenHandler = articleReadOnOpenHandler(
            for: appState.currentArticleListSessionReference
        )
        await controller.load(
            articleID: transitionContext.targetArticleID,
            dependencies: dependencies,
            preservesCurrentArticleDuringLoading: true,
            articleReadOnOpenHandler: readOnOpenHandler
        )
        pendingAdjacentArticleOverscrollDirection = nil
        adjacentArticleOverscrollState = ReaderArticleOverscrollNavigationState()
        await resetAdjacentArticleTransitionDirectionAfterAnimation(
            transitionContext: transitionContext
        )
    }

    private func resetAdjacentArticleTransitionDirectionAfterAnimation(
        transitionContext: AdjacentArticleTransitionContext?
    ) async {
        guard let transitionContext,
              adjacentArticleTransitionContext == transitionContext else {
            return
        }

        do {
            try await Task.sleep(for: .milliseconds(320))
        } catch {
            return
        }
        clearAdjacentArticleTransitionContext(transitionContext)
    }

    private func clearAdjacentArticleTransitionContext(
        _ transitionContext: AdjacentArticleTransitionContext
    ) {
        guard adjacentArticleTransitionContext == transitionContext else { return }
        adjacentArticleTransitionContext = nil
    }

    @MainActor
    private func articleReadOnOpenHandler(
        for listSession: ArticleListSessionReference?
    ) -> ArticleReadOnOpenHandler? {
        guard let listSession else { return nil }

        return { articleID, persistedState in
            appState.recordArticleReadOnOpen(
                articleID,
                isRead: persistedState.isRead,
                in: listSession
            )
        }
    }

    private var actionHandlers: ArticleScreenActionHandlers {
        ArticleScreenActionHandlers(
            toggleReadStatus: {
                _controller.wrappedValue.toggleArticleReadStatus(
                    dependencies: dependencies,
                    isPreviewMode: previewScreenState != nil
                )
            },
            toggleStarredStatus: {
                _controller.wrappedValue.toggleArticleStarredStatus(
                    dependencies: dependencies,
                    isPreviewMode: previewScreenState != nil
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

    @MainActor
    private func handlePreviousArticleTap() {
        navigateToAdjacentArticle(.previous)
    }

    @MainActor
    private func handleNextArticleTap() {
        navigateToAdjacentArticle(.next)
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

private struct AdjacentArticleTransitionContext: Equatable {
    let generation: Int
    let direction: ReaderAdjacentArticleNavigationDirection
    let sourceArticleID: UUID
    let targetArticleID: UUID
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
