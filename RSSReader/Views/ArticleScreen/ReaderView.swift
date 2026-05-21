import SwiftUI
import UIKit

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
    @State private var adjacentNavigationControlsMode: ReaderAdjacentNavigationControlsMode = .swipesAndToolbarControls
    @State private var adjacentArticleTransitionDirection: ReaderAdjacentArticleNavigationDirection?
    @State private var pendingAdjacentArticleOverscrollDirection: ReaderAdjacentArticleNavigationDirection?
    @State private var adjacentArticleOverscrollState = ReaderArticleOverscrollNavigationState()
    @State private var adjacentArticleOverscrollReadyHapticTrigger = 0
    @State private var hasTriggeredAdjacentArticleOverscrollReadyHaptic = false

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
                contentSurface(
                    viewState,
                    contentSafeAreaInsets: geometryProxy.safeAreaInsets
                )
                .id(contentTransitionID)
                .transition(articleTransition)
            }
            .overlay(alignment: .top) {
                adjacentArticleOverscrollIndicator(
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
                adjacentArticleOverscrollIndicator(
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

                if adjacentNavigationControlsMode.showsToolbarControls {
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
                }

                ToolbarItem(placement: .bottomBar) {
                    Button(action: handleOpenSourceArticleTap) {
                        Image(systemName: bottomActions.openSourceArticleSystemImage)
                    }
                    .disabled(bottomActions.canOpenSourceArticle == false)
                    .accessibilityLabel(bottomActions.openSourceArticleTitle)
                }
            }
        }
        .task(id: ArticleScreenLoadContext(articleID: currentArticleID, reloadID: reloadID)) {
            guard previewScreenState == nil else { return }
            loadReaderAdjacentNavigationControlsMode()
            await controller.load(
                articleID: currentArticleID,
                dependencies: dependencies,
                preservesCurrentArticleDuringLoading: adjacentArticleTransitionDirection != nil
            )
            pendingAdjacentArticleOverscrollDirection = nil
            adjacentArticleOverscrollState = ReaderArticleOverscrollNavigationState()
            await resetAdjacentArticleTransitionDirectionAfterAnimation()
        }
        .onChange(of: appState.isPresentingSettingsScreen) { _, isPresentingSettingsScreen in
            guard previewScreenState == nil, isPresentingSettingsScreen == false else { return }
            loadReaderAdjacentNavigationControlsMode()
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

    @ViewBuilder
    private func contentSurface(
        _ viewState: ArticleScreenDerivedViewState,
        contentSafeAreaInsets: EdgeInsets
    ) -> some View {
        Group {
            if let content = viewState.content {
                ScrollView {
                    articleContent(content)
                        .padding(.horizontal, ReaderChromeUnderlayLayout.contentMargin)
                        .padding(.top, contentSafeAreaInsets.top + ReaderChromeUnderlayLayout.contentMargin)
                        .padding(.bottom, contentSafeAreaInsets.bottom + ReaderChromeUnderlayLayout.contentMargin)
                }
                .ignoresSafeArea(.container, edges: [.top, .bottom])
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

    @ViewBuilder
    private func articleContent(_ content: ArticleScreenContentState) -> some View {
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
            preservesCurrentArticleDuringLoading: true
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
        if progress >= ReaderChromeUnderlayLayout.indicatorVisibilityThreshold {
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
            CachedArticleImageView(url: url)
                .id(url)
        case .fallbackNotice(let message):
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
    }
}

struct CachedArticleImageView: View {
    let url: URL
    @State private var phase: CachedArticleImagePhase

    @MainActor
    init(url: URL) {
        self.init(url: url, cache: ArticleImageMemoryCache.shared)
    }

    @MainActor
    init(url: URL, cache: ArticleImageMemoryCache) {
        self.url = url

        if let cachedImage = cache.image(for: url) {
            self._phase = State(initialValue: .success(cachedImage))
        } else {
            self._phase = State(initialValue: .empty)
        }
    }

    var body: some View {
        content
            .task(id: url) {
                await loadImage()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .empty, .loading:
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.quaternary.opacity(0.4))
                ProgressView()
            }
            .frame(maxWidth: .infinity)
            .frame(height: 220)
        case .success(let image):
            Image(uiImage: image)
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
        }
    }

    @MainActor
    private func loadImage() async {
        let memoryCache = ArticleImageMemoryCache.shared
        let diskCache = ArticleImageDiskCache.shared

        if let cachedImage = memoryCache.image(for: url) {
            phase = .success(cachedImage)
            return
        }

        phase = .loading

        do {
            if let cachedData = try? await diskCache.data(for: url),
               let diskImage = UIImage(data: cachedData) {
                memoryCache.insert(diskImage, for: url, cost: cachedData.count)
                phase = .success(diskImage)
                return
            }

            let (data, response) = try await URLSession.shared.data(from: url)
            try Task.checkCancellation()

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  let image = UIImage(data: data) else {
                phase = .failure
                return
            }

            try? await diskCache.insert(data, for: url)
            memoryCache.insert(image, for: url, cost: data.count)
            phase = .success(image)
        } catch is CancellationError {
            return
        } catch {
            phase = .failure
        }
    }
}

enum CachedArticleImagePhase {
    case empty
    case loading
    case success(UIImage)
    case failure
}

@MainActor
final class ArticleImageMemoryCache {
    static let shared = ArticleImageMemoryCache()

    private let storage = NSCache<NSURL, UIImage>()
    private var storedURLs: Set<URL> = []

    init(countLimit: Int = 256, totalCostLimit: Int = 80 * 1024 * 1024) {
        storage.countLimit = countLimit
        storage.totalCostLimit = totalCostLimit
    }

    func image(for url: URL) -> UIImage? {
        guard let image = storage.object(forKey: url as NSURL) else {
            storedURLs.remove(url)
            return nil
        }

        return image
    }

    func insert(_ image: UIImage, for url: URL, cost: Int = 0) {
        storage.setObject(image, forKey: url as NSURL, cost: cost)
        storedURLs.insert(url)
    }

    var hasImages: Bool {
        storedURLs.isEmpty == false
    }

    func removeAllImages() {
        storage.removeAllObjects()
        storedURLs.removeAll()
    }
}

private struct ArticleScreenLoadContext: Hashable {
    let articleID: UUID?
    let reloadID: UUID
}

private extension ReaderAdjacentNavigationControlsMode {
    var showsToolbarControls: Bool {
        switch self {
        case .toolbarControlsOnly, .swipesAndToolbarControls:
            true
        case .swipesOnly:
            false
        }
    }

    var allowsAdjacentArticleSwipes: Bool {
        switch self {
        case .swipesOnly, .swipesAndToolbarControls:
            true
        case .toolbarControlsOnly:
            false
        }
    }
}

private enum ReaderChromeUnderlayLayout {
    static let contentMargin: CGFloat = 16
    static let indicatorChromeSpacing: CGFloat = 12
    static let indicatorVisibilityThreshold: CGFloat = 0.18
}
