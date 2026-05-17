import SwiftUI

struct ArticleScreenActionHandlers {
    let toggleReadStatus: () -> Void
    let toggleStarredStatus: () -> Void
    let openSourceArticle: () -> Void
    let bodyLinkTapped: (URL) -> Void
}

struct ReaderView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.appDependencies) private var dependencies
    @Environment(\.appThemeVariant) private var appThemeVariant
    @Environment(\.openURL) private var openURL
    let articleID: UUID?
    let reloadID: UUID
    let showsBackButton: Bool
    let navigateBackToArticles: () -> Void
    let previewScreenState: ArticleScreenState?
    @State private var controller = ArticleScreenController()
    @State private var adjacentArticleTransitionDirection: ReaderAdjacentArticleNavigationDirection?
    @State private var pendingAdjacentArticleOverscrollDirection: ReaderAdjacentArticleNavigationDirection?
    @State private var adjacentArticleOverscrollState = ReaderArticleOverscrollNavigationState()

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
        let viewState = controller.screenState.derivedViewState(selectedArticleID: articleID)

        ZStack {
            contentSurface(viewState)
                .id(articleID)
                .transition(articleTransition)
        }
        .overlay(alignment: .top) {
            adjacentArticleOverscrollIndicator(
                systemImage: "chevron.up",
                progress: adjacentArticleOverscrollState.previousProgress,
                isReady: adjacentArticleOverscrollState.previousProgress >= 1
            )
            .padding(.top, 12)
        }
        .overlay(alignment: .bottom) {
            adjacentArticleOverscrollIndicator(
                systemImage: "chevron.down",
                progress: adjacentArticleOverscrollState.nextProgress,
                isReady: adjacentArticleOverscrollState.nextProgress >= 1
            )
            .padding(.bottom, 12)
        }
        .animation(.snappy(duration: 0.28), value: articleID)
        .clipped()
        .background(appThemeVariant.primaryBackground.ignoresSafeArea())
        .toolbarTitleDisplayMode(.inline)
        .navigationTitle("")
        .toolbar {
            if viewState.toolbarActions.showsShareAction {
                ToolbarItem(placement: .topBarTrailing) {
                    if let shareURL = viewState.toolbarActions.shareURL {
                        ShareLink(item: shareURL) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Share")
                    } else {
                        Button(action: {}) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .disabled(true)
                        .accessibilityLabel("Share")
                    }
                }
            }

            if viewState.toolbarActions.showsBottomActions,
               let bottomActions = viewState.toolbarActions.bottomActions {
                ToolbarItem(placement: .bottomBar) {
                    Button(action: handleMarkUnreadActionTap) {
                        Image(systemName: bottomActions.readToggleSystemImage)
                    }
                    .accessibilityLabel(bottomActions.readToggleTitle)
                }

                ToolbarSpacer(placement: .bottomBar)

                ToolbarItem(placement: .bottomBar) {
                    Button(action: handleStarActionTap) {
                        Image(systemName: bottomActions.starSystemImage)
                    }
                    .accessibilityLabel(bottomActions.starTitle)
                }

                ToolbarSpacer(placement: .bottomBar)

                ToolbarItem(placement: .bottomBar) {
                    Button(action: handleNextArticleTap) {
                        Image(systemName: "chevron.down")
                    }
                    .disabled(appState.adjacentArticleID(.next) == nil)
                    .accessibilityLabel("Next Article")
                }

                ToolbarSpacer(placement: .bottomBar)

                ToolbarItem(placement: .bottomBar) {
                    Button(action: handlePreviousArticleTap) {
                        Image(systemName: "chevron.up")
                    }
                    .disabled(appState.adjacentArticleID(.previous) == nil)
                    .accessibilityLabel("Previous Article")
                }

                ToolbarSpacer(placement: .bottomBar)

                ToolbarItem(placement: .bottomBar) {
                    Button(action: handleOpenSourceArticleTap) {
                        Image(systemName: bottomActions.openSourceArticleSystemImage)
                    }
                    .disabled(bottomActions.canOpenSourceArticle == false)
                    .accessibilityLabel(bottomActions.openSourceArticleTitle)
                }
            }
        }
        .task(id: ArticleScreenLoadContext(articleID: articleID, reloadID: reloadID)) {
            guard previewScreenState == nil else { return }
            await controller.load(articleID: articleID, dependencies: dependencies)
            adjacentArticleTransitionDirection = nil
            pendingAdjacentArticleOverscrollDirection = nil
            adjacentArticleOverscrollState = ReaderArticleOverscrollNavigationState()
        }
        .simultaneousGesture(backNavigationGesture)
    }

    @ViewBuilder
    private func contentSurface(_ viewState: ArticleScreenDerivedViewState) -> some View {
        Group {
            if let content = viewState.content {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let publishedAtText = content.header.publishedAtText {
                            Text(publishedAtText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Text(content.header.title)
                            .font(.title2.weight(.semibold))

                        if let author = content.header.author {
                            Text(author)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        if let feedTitle = content.header.feedTitle {
                            Text(feedTitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        ForEach(Array(content.body.blocks.enumerated()), id: \.offset) { _, block in
                            bodyBlockView(block)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                }
                .onScrollGeometryChange(for: ReaderArticleScrollGeometry.self) { geometry in
                    ReaderArticleScrollGeometry(
                        contentHeight: geometry.contentSize.height,
                        containerHeight: geometry.containerSize.height,
                        contentOffsetY: geometry.contentOffset.y,
                        contentInsetTop: geometry.contentInsets.top,
                        contentInsetBottom: geometry.contentInsets.bottom,
                        boundsMaxY: geometry.bounds.maxY
                    )
                } action: { _, newGeometry in
                    handleArticleScrollGeometryChange(newGeometry)
                }
                .onScrollPhaseChange { oldPhase, newPhase, _ in
                    handleArticleScrollPhaseChange(oldPhase: oldPhase, newPhase: newPhase)
                }
            } else if let primaryLoadingState = viewState.primaryLoadingState {
                ScreenLoadingView(title: primaryLoadingState.title)
            } else if let placeholder = viewState.placeholder {
                ScreenPlaceholderView(
                    title: placeholder.title,
                    systemImage: placeholder.systemImage,
                    description: placeholder.description
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    translation: value.translation
                ) else {
                    return
                }
                navigateBackToArticles()
            }
    }

    private func handleArticleScrollGeometryChange(_ scrollGeometry: ReaderArticleScrollGeometry) {
        guard previewScreenState == nil else { return }
        let overscrollState = ArticleScreenNavigationState.adjacentArticleOverscrollState(
            scrollGeometry: scrollGeometry
        )
        adjacentArticleOverscrollState = effectiveAdjacentArticleOverscrollState(overscrollState)
        pendingAdjacentArticleOverscrollDirection = adjacentArticleOverscrollState.readyDirection
    }

    private func handleArticleScrollPhaseChange(oldPhase: ScrollPhase, newPhase: ScrollPhase) {
        guard previewScreenState == nil else { return }
        if newPhase == .tracking || newPhase == .interacting {
            pendingAdjacentArticleOverscrollDirection = nil
            adjacentArticleOverscrollState = ReaderArticleOverscrollNavigationState()
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
    private func handleMarkUnreadActionTap() {
        actionHandlers.toggleReadStatus()
    }

    @MainActor
    private func handleStarActionTap() {
        actionHandlers.toggleStarredStatus()
    }

    @MainActor
    private func handleOpenSourceArticleTap() {
        actionHandlers.openSourceArticle()
    }

    @MainActor
    private func handlePreviousArticleTap() {
        navigateToAdjacentArticle(.previous)
    }

    @MainActor
    private func handleNextArticleTap() {
        navigateToAdjacentArticle(.next)
    }

    @ViewBuilder
    private func adjacentArticleOverscrollIndicator(
        systemImage: String,
        progress: CGFloat,
        isReady: Bool
    ) -> some View {
        if progress > 0 {
            Image(systemName: isReady ? systemImage : "minus")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(isReady ? .primary : .secondary)
                .contentTransition(
                    .symbolEffect(
                        .replace.magic(fallback: .downUp.byLayer),
                        options: .nonRepeating
                    )
                )
                .scaleEffect(0.4 + 0.6 * progress)
                .opacity(0.25 + 0.75 * progress)
                .animation(.snappy(duration: 0.18), value: isReady)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func bodyBlockView(_ block: ArticleScreenBodyBlock) -> some View {
        switch block {
        case .paragraph(let text):
            Text(text.attributedString)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .environment(\.openURL, OpenURLAction { url in
                    actionHandlers.bodyLinkTapped(url)
                    return .handled
                })
        case .image(let url):
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.quaternary.opacity(0.4))
                        ProgressView()
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                case .failure:
                    ContentUnavailableView(
                        "Image Unavailable",
                        systemImage: "photo",
                        description: Text("The article image could not be loaded.")
                    )
                @unknown default:
                    EmptyView()
                }
            }
        case .fallbackNotice(let message):
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
    }
}

private struct ArticleScreenLoadContext: Hashable {
    let articleID: UUID?
    let reloadID: UUID
}
