import SwiftUI

struct ReaderView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.appDependencies) private var dependencies
    @Environment(\.appThemeVariant) private var appThemeVariant
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.openURL) private var openURL
    let articleID: UUID?
    let reloadID: UUID
    let showsBackButton: Bool
    let navigateBackToArticles: () -> Void
    let previewScreenState: ArticleScreenState?
    @State private var controller = ArticleScreenController()
    @State private var adjacentNavigationControlsMode: ReaderAdjacentNavigationControlsMode = .swipesAndToolbarControls
    @State private var adjacentArticleTransitionDirection: ReaderAdjacentArticleNavigationDirection?
    @State private var pendingAdjacentArticleOverscrollDirection: ReaderAdjacentArticleNavigationDirection?
    @State private var adjacentArticleOverscrollState = ReaderArticleOverscrollNavigationState()
    @State private var adjacentArticleOverscrollReadyHapticTrigger = 0
    @State private var hasTriggeredAdjacentArticleOverscrollReadyHaptic = false
    @State private var backNavigationContainerWidth: CGFloat = 0

    init(
        articleID: UUID?,
        reloadID: UUID = UUID(),
        showsBackButton: Bool,
        navigateBackToArticles: @escaping () -> Void,
        previewScreenState: ArticleScreenState? = nil
    ) {
        self.articleID = articleID
        self.reloadID = reloadID
        self.showsBackButton = showsBackButton
        self.navigateBackToArticles = navigateBackToArticles
        self.previewScreenState = previewScreenState
        self._controller = State(initialValue: ArticleScreenController(previewScreenState: previewScreenState))
    }

    var body: some View {
        let currentArticleID = resolvedArticleID
        let preservesStaleContent = adjacentArticleTransitionDirection != nil
        let viewState = controller.screenState.derivedViewState(
            selectedArticleID: currentArticleID,
            preservesStaleContent: preservesStaleContent
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
        .animation(.snappy(duration: 0.28), value: contentTransitionID)
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
                nextArticleID: appState.adjacentArticleID(.next),
                actionHandlers: actionHandlers,
                onPreviousArticleTap: handlePreviousArticleTap,
                onNextArticleTap: handleNextArticleTap
            )
        }
        .task(id: ArticleScreenLoadContext(articleID: currentArticleID, reloadID: reloadID)) {
            guard previewScreenState == nil else { return }
            loadReaderAdjacentNavigationControlsMode()
            await controller.load(
                articleID: currentArticleID,
                dependencies: dependencies,
                preservesCurrentArticleDuringLoading: adjacentArticleTransitionDirection != nil,
                articleReadOnOpenHandler: recordArticleReadOnOpenInCurrentListSession
            )
            pendingAdjacentArticleOverscrollDirection = nil
            adjacentArticleOverscrollState = ReaderArticleOverscrollNavigationState()
            await resetAdjacentArticleTransitionDirectionAfterAnimation()
        }
        .onChange(of: appState.isPresentingSettingsScreen) { _, isPresentingSettingsScreen in
            guard previewScreenState == nil, isPresentingSettingsScreen == false else { return }
            loadReaderAdjacentNavigationControlsMode()
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            backNavigationContainerWidth = newWidth
        }
        .simultaneousGesture(backNavigationGesture)
    }

    private var resolvedArticleID: UUID? {
        previewScreenState == nil ? appState.selectedArticleID : articleID
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
        switch adjacentArticleTransitionDirection {
        case .next:
            .asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity),
                removal: .move(edge: .top).combined(with: .opacity)
            )
        case .previous:
            .asymmetric(
                insertion: .move(edge: .top).combined(with: .opacity),
                removal: .move(edge: .bottom).combined(with: .opacity)
            )
        case .none:
            .opacity
        }
    }

    private var backNavigationGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                guard showsBackButton else { return }
                guard ArticleScreenNavigationState.shouldNavigateBackOnDrag(
                    startLocationX: value.startLocation.x,
                    containerWidth: backNavigationContainerWidth,
                    layoutDirection: layoutDirection,
                    translation: value.translation
                ) else {
                    return
                }
                navigateBackToArticles()
            }
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
            nextProgress: appState.adjacentArticleID(.next) == nil ? 0 : overscrollState.nextProgress
        )
    }

    private func navigateToAdjacentArticle(_ direction: ReaderAdjacentArticleNavigationDirection) {
        adjacentArticleTransitionDirection = direction

        var didSelectAdjacentArticle = false
        withAnimation(.snappy(duration: 0.28)) {
            didSelectAdjacentArticle = appState.selectAdjacentArticle(direction)
        }

        if didSelectAdjacentArticle == false {
            adjacentArticleTransitionDirection = nil
            return
        }

        Task {
            await loadCurrentArticleAfterAdjacentNavigationIfNeeded()
        }
    }

    @MainActor
    private func loadCurrentArticleAfterAdjacentNavigationIfNeeded() async {
        try? await Task.sleep(for: .milliseconds(80))
        let currentArticleID = resolvedArticleID
        guard controller.screenState.article?.id != currentArticleID else {
            await resetAdjacentArticleTransitionDirectionAfterAnimation()
            return
        }

        await controller.load(
            articleID: currentArticleID,
            dependencies: dependencies,
            preservesCurrentArticleDuringLoading: true,
            articleReadOnOpenHandler: recordArticleReadOnOpenInCurrentListSession
        )
        pendingAdjacentArticleOverscrollDirection = nil
        adjacentArticleOverscrollState = ReaderArticleOverscrollNavigationState()
        await resetAdjacentArticleTransitionDirectionAfterAnimation()
    }

    private func resetAdjacentArticleTransitionDirectionAfterAnimation() async {
        guard adjacentArticleTransitionDirection != nil else { return }
        try? await Task.sleep(for: .milliseconds(320))
        adjacentArticleTransitionDirection = nil
    }

    @MainActor
    private func recordArticleReadOnOpenInCurrentListSession(_ articleID: UUID) {
        appState.recordArticleReadOnOpenInCurrentListSession(articleID)
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
