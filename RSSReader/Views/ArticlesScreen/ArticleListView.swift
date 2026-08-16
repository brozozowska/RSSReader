import SwiftUI

// MARK: - ArticleListView

struct ArticleListView: View {
    @Environment(\.appDependencies) private var dependencies
    @Environment(AppState.self) private var appState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let selectedSidebarSelection: SidebarSelection?
    let selectedSidebarArticleFilter: SidebarArticleFilter
    let reloadID: UUID
    let previewScreenState: ArticlesScreenState?

    @Binding var selection: UUID?
    @State private var controller: ArticlesScreenController
    @State private var searchText = ""
    @State private var refreshStartHapticTrigger = 0
    @State private var lastScopeMetricReloadContext: ArticleScopeMetricReloadContext?

    init(
        selectedSidebarSelection: SidebarSelection?,
        selectedSidebarArticleFilter: SidebarArticleFilter,
        reloadID: UUID,
        controller: ArticlesScreenController? = nil,
        previewScreenState: ArticlesScreenState?,
        selection: Binding<UUID?>
    ) {
        self.selectedSidebarSelection = selectedSidebarSelection
        self.selectedSidebarArticleFilter = selectedSidebarArticleFilter
        self.reloadID = reloadID
        self.previewScreenState = previewScreenState
        self._selection = selection
        self._controller = State(
            initialValue: controller ?? ArticlesScreenController(previewScreenState: previewScreenState)
        )
    }

    // MARK: Body

    var body: some View {
        let derivedViewState = controller.screenState.derivedViewState()

        ArticleListContentView(
            sections: derivedViewState.sections,
            animationState: derivedViewState.listAnimationState,
            customRefreshState: derivedViewState.customRefreshState,
            canLoadNextPage: controller.screenState.canLoadNextPage,
            isLoadingNextPage: controller.screenState.isLoadingNextPage,
            selection: $selection,
            scrollPositionID: articleListScrollPositionBinding,
            customRefreshPullProgressChanged: updateCustomRefreshPullProgress,
            customRefreshReleaseAction: triggerCustomRefresh,
            loadNextPageAction: loadNextPage,
            toggleReadStatusAction: toggleArticleReadStatus,
            toggleStarredAction: toggleStarredState
        )
        .toolbarTitleDisplayMode(.inline)
        .applySearchableToolbar(
            isEnabled: derivedViewState.toolbarActions.showsSearchAction,
            text: $searchText
        )
        .toolbar {
            ToolbarItem(placement: .principal) {
                navigationChromeView(derivedViewState.navigationChrome)
            }

            if derivedViewState.toolbarActions.showsMarkAllAsReadAction {
                ToolbarItem(placement: .bottomBar) {
                    Button(action: handleMarkAllAsReadAction) {
                        Image(systemName: "checkmark.circle.fill")
                    }
                    .disabled(derivedViewState.toolbarActions.isMarkAllAsReadEnabled == false)
                    .accessibilityLabel(ReadingLocalization.markAllAsReadAccessibilityLabel)
                }
            }

            if derivedViewState.toolbarActions.showsMarkAllAsReadAction
                && derivedViewState.toolbarActions.showsSearchAction {
                ToolbarSpacer(placement: .bottomBar)
            }

            if derivedViewState.toolbarActions.showsSearchAction {
                DefaultToolbarItem(kind: .search, placement: .bottomBar)
            }
        }
        .alert(
            ReadingLocalization.markAllAsReadDialogTitle,
            isPresented: markAllAsReadConfirmationIsPresented
        ) {
            Button(ReadingLocalization.markAllAsReadDialogAction, role: .destructive, action: confirmMarkAllAsRead)
            Button(ReadingLocalization.cancelAction, role: .cancel) {}
        } message: {
            Text(ReadingLocalization.markAllAsReadDialogMessage)
        }
        .overlay {
            overlayContent(using: derivedViewState)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            ArticleListRefreshBanner(
                state: derivedViewState.refreshBanner,
                retryAction: refreshCurrentSelection,
                dismissAction: dismissRefreshFeedback
            )
        }
        .task(id: ArticleListLoadContext(
            sidebarSelection: selectedSidebarSelection,
            sidebarArticleFilter: selectedSidebarArticleFilter,
            normalizedSearchText: ArticleSearchScope.normalizedSearchText(searchText),
            reloadID: reloadID
        )) {
            guard isPreviewMode == false else { return }
            await loadArticles(retainsSessionFilterMutations: true)
        }
        .onChange(of: selectedSidebarSelection) { oldValue, newValue in
            guard oldValue != newValue, searchText.isEmpty == false else { return }
            searchText = ""
        }
        .onChange(of: selection) { _, newValue in
            guard let newValue else { return }
            appState.updateArticleListScrollPosition(
                newValue,
                sidebarSelection: selectedSidebarSelection,
                sidebarArticleFilter: selectedSidebarArticleFilter
            )
        }
        .onChange(of: appState.articleReadOnOpenEvent) { _, event in
            applyArticleReadOnOpenEvent(event)
        }
        .sensoryFeedback(
            .impact(flexibility: .solid, intensity: 0.65),
            trigger: refreshStartHapticTrigger
        )
    }

    // MARK: Loading

    @MainActor
    private func loadArticles(
        retainsSessionFilterMutations: Bool = true,
        retainedSessionMembershipStatus: ArticleListEntryMembershipStatus = .retainedAfterFilterMutation,
        preservesRefreshFeedback: Bool = false,
        refreshesScopeMetric: Bool? = nil
    ) async {
        let loadingSidebarSelection = selectedSidebarSelection
        let loadingSidebarArticleFilter = selectedSidebarArticleFilter
        let loadingNormalizedSearchText = ArticleSearchScope.normalizedSearchText(searchText)
        let loadingReloadID = reloadID
        let scopeMetricReloadContext = ArticleScopeMetricReloadContext(
            selection: loadingSidebarSelection,
            sidebarArticleFilter: loadingSidebarArticleFilter,
            reloadID: loadingReloadID
        )
        let shouldRefreshScopeMetric = refreshesScopeMetric
            ?? (
                lastScopeMetricReloadContext != scopeMetricReloadContext
                    || (
                        controller.screenState.articleListSession.scopeMetric == nil
                            && loadingNormalizedSearchText.isEmpty
                    )
            )
        if shouldRefreshScopeMetric {
            lastScopeMetricReloadContext = scopeMetricReloadContext
        }

        await controller.load(
            selection: loadingSidebarSelection,
            sidebarArticleFilter: loadingSidebarArticleFilter,
            searchText: searchText,
            dependencies: dependencies,
            refreshesScopeMetric: shouldRefreshScopeMetric,
            retainsSessionFilterMutations: retainsSessionFilterMutations,
            retainedSessionMembershipStatus: retainedSessionMembershipStatus,
            preservesRefreshFeedback: preservesRefreshFeedback
        )

        guard loadingSidebarSelection == appState.selectedSidebarSelection,
              loadingSidebarArticleFilter == appState.selectedSidebarArticleFilter,
              loadingNormalizedSearchText == ArticleSearchScope.normalizedSearchText(searchText),
              loadingReloadID == appState.articleListReloadID else {
            return
        }

        let visibleArticleIDs = controller.visibleArticleIDs()
        selection = stabilizedSelection(availableArticleIDs: visibleArticleIDs)
        syncArticleNavigationContext(visibleArticleIDs)
    }

    @MainActor
    private func loadNextPage() async {
        guard isPreviewMode == false,
              controller.screenState.canLoadNextPage else {
            return
        }

        let loadingSidebarSelection = selectedSidebarSelection
        let loadingSidebarArticleFilter = selectedSidebarArticleFilter
        await controller.loadNextPage(dependencies: dependencies)

        guard loadingSidebarSelection == appState.selectedSidebarSelection,
              loadingSidebarArticleFilter == appState.selectedSidebarArticleFilter else {
            return
        }

        let visibleArticleIDs = controller.visibleArticleIDs()
        selection = stabilizedSelection(availableArticleIDs: visibleArticleIDs)
        syncArticleNavigationContext(visibleArticleIDs)
    }

    // MARK: Selection

    private func stabilizedSelection(availableArticleIDs: [UUID]) -> UUID? {
        if let selection, availableArticleIDs.contains(selection) {
            return selection
        }
        guard horizontalSizeClass != .compact else {
            return nil
        }
        return availableArticleIDs.first
    }

    private func syncArticleNavigationContext(_ visibleArticleIDs: [UUID]) {
        guard isPreviewMode == false else { return }
        reconcileArticleListScrollPosition(visibleArticleIDs: visibleArticleIDs)
        appState.updateArticleNavigationContext(
            visibleArticleIDs,
            sidebarSelection: selectedSidebarSelection,
            sidebarArticleFilter: selectedSidebarArticleFilter,
            articleListSessionID: controller.currentArticleListSessionID
        )
    }

    private func navigationChromeView(
        _ navigationChrome: ArticlesScreenNavigationChromeState
    ) -> some View {
        VStack(spacing: 0) {
            Text(navigationChrome.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .center)

            Text(navigationChrome.subtitle.isEmpty ? " " : navigationChrome.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .opacity(navigationChrome.subtitle.isEmpty ? 0 : 1)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .multilineTextAlignment(.center)
        .frame(width: 240, height: 44, alignment: .center)
        .fixedSize(horizontal: true, vertical: false)
        .contentTransition(.identity)
        .accessibilityElement(children: .combine)
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private var articleListScrollPositionBinding: Binding<UUID?> {
        Binding(
            get: {
                appState.articleListScrollPositionID(
                    sidebarSelection: selectedSidebarSelection,
                    sidebarArticleFilter: selectedSidebarArticleFilter
                )
            },
            set: { articleID in
                appState.updateArticleListScrollPosition(
                    articleID,
                    sidebarSelection: selectedSidebarSelection,
                    sidebarArticleFilter: selectedSidebarArticleFilter
                )
            }
        )
    }

    private func reconcileArticleListScrollPosition(visibleArticleIDs: [UUID]) {
        let currentScrollPositionID = appState.articleListScrollPositionID(
            sidebarSelection: selectedSidebarSelection,
            sidebarArticleFilter: selectedSidebarArticleFilter
        )
        guard let currentScrollPositionID,
              visibleArticleIDs.contains(currentScrollPositionID) == false else {
            return
        }

        appState.updateArticleListScrollPosition(
            nil,
            sidebarSelection: selectedSidebarSelection,
            sidebarArticleFilter: selectedSidebarArticleFilter
        )
    }

    // MARK: Confirmation

    private var markAllAsReadConfirmationIsPresented: Binding<Bool> {
        Binding(
            get: { controller.screenState.pendingConfirmation == .markAllAsRead },
            set: { isPresented in
                if isPresented == false {
                    controller.screenState.dismissConfirmation()
                }
            }
        )
    }

    @MainActor
    private func handleMarkAllAsReadAction() {
        Task { @MainActor in
            await controller.handleMarkAllAsReadAction(
                searchText: searchText,
                selection: selectedSidebarSelection,
                sidebarArticleFilter: selectedSidebarArticleFilter,
                dependencies: dependencies,
                isPreviewMode: isPreviewMode
            )
            if isPreviewMode == false {
                appState.requestSidebarReload()
            }
            let visibleArticleIDs = controller.visibleArticleIDs()
            selection = stabilizedSelection(availableArticleIDs: visibleArticleIDs)
            syncArticleNavigationContext(visibleArticleIDs)
        }
    }

    // MARK: Bulk Actions

    @MainActor
    private func confirmMarkAllAsRead() {
        Task { @MainActor in
            await controller.confirmMarkAllAsRead(
                searchText: searchText,
                selection: selectedSidebarSelection,
                sidebarArticleFilter: selectedSidebarArticleFilter,
                dependencies: dependencies,
                isPreviewMode: isPreviewMode
            )
            if isPreviewMode == false {
                appState.requestSidebarReload()
            }
            let visibleArticleIDs = controller.visibleArticleIDs()
            selection = stabilizedSelection(availableArticleIDs: visibleArticleIDs)
            syncArticleNavigationContext(visibleArticleIDs)
        }
    }

    // MARK: Row Actions

    @MainActor
    private func toggleArticleReadStatus(_ article: ArticleListItemDTO) {
        controller.toggleArticleReadStatus(
            article,
            selection: selectedSidebarSelection,
            sidebarArticleFilter: selectedSidebarArticleFilter,
            dependencies: dependencies,
            isPreviewMode: isPreviewMode
        )
        let visibleArticleIDs = controller.visibleArticleIDs()
        selection = stabilizedSelection(availableArticleIDs: visibleArticleIDs)
        syncArticleNavigationContext(visibleArticleIDs)
    }

    @MainActor
    private func toggleStarredState(for article: ArticleListItemDTO) {
        controller.toggleStarredState(
            for: article,
            selection: selectedSidebarSelection,
            sidebarArticleFilter: selectedSidebarArticleFilter,
            dependencies: dependencies,
            isPreviewMode: isPreviewMode
        )
        let visibleArticleIDs = controller.visibleArticleIDs()
        selection = stabilizedSelection(availableArticleIDs: visibleArticleIDs)
        syncArticleNavigationContext(visibleArticleIDs)
    }

    @MainActor
    private func applyArticleReadOnOpenEvent(_ event: ArticleReadOnOpenEvent?) {
        guard let event else { return }
        guard controller.applyArticleReadOnOpenEvent(event) else {
            return
        }
        let visibleArticleIDs = controller.visibleArticleIDs()
        selection = stabilizedSelection(availableArticleIDs: visibleArticleIDs)
        syncArticleNavigationContext(visibleArticleIDs)
    }

    // MARK: Search And Overlay

    private var isPreviewMode: Bool {
        previewScreenState != nil
    }

    @ViewBuilder
    private func overlayContent(using derivedViewState: ArticlesScreenDerivedViewState) -> some View {
        if let loadingState = derivedViewState.primaryLoadingState {
            ScreenLoadingView(title: loadingState.title)
        } else if let placeholder = derivedViewState.searchPlaceholder {
            ScreenPlaceholderView(
                title: placeholder.title,
                systemImage: placeholder.systemImage,
                description: placeholder.description
            )
        } else if let primaryFailureMessage = controller.screenState.primaryFailureMessage {
            ScreenPlaceholderView(
                title: ReadingLocalization.unableToLoadArticlesTitle,
                systemImage: "exclamationmark.triangle",
                description: primaryFailureMessage
            )
        } else if let placeholder = controller.screenState.placeholder {
            ScreenPlaceholderView(
                title: placeholder.title,
                systemImage: placeholder.systemImage,
                description: placeholder.description
            )
        }
    }

    private func retryPrimaryLoad() {
        Task {
            await loadArticles(retainsSessionFilterMutations: true)
        }
    }

    // MARK: Refresh

    @MainActor
    private func refreshCurrentSelection() async {
        guard isPreviewMode == false else { return }

        refreshStartHapticTrigger += 1

        await controller.refreshCurrentSelection(
            selection: selectedSidebarSelection,
            dependencies: dependencies,
            appState: appState,
            requestsArticleListReload: false
        )
        let preservesRefreshFeedback = controller.screenState.refreshFeedback != nil

        await loadArticles(
            retainsSessionFilterMutations: false,
            retainedSessionMembershipStatus: .retainedAfterRefresh,
            preservesRefreshFeedback: preservesRefreshFeedback,
            refreshesScopeMetric: true
        )
    }

    @MainActor
    private func updateCustomRefreshPullProgress(_ progress: Double) {
        controller.screenState.updateCustomRefreshPullProgress(progress)
    }

    @MainActor
    private func triggerCustomRefresh() async {
        guard isPreviewMode == false else { return }
        guard controller.screenState.customRefreshState.phase == .ready else { return }

        controller.screenState.beginCustomRefresh()
        defer {
            controller.screenState.endCustomRefresh()
        }

        await refreshCurrentSelection()
    }

    @MainActor
    private func dismissRefreshFeedback() {
        controller.screenState.dismissRefreshFeedback()
    }
}

private struct ArticleScopeMetricReloadContext: Equatable {
    let selection: SidebarSelection?
    let sidebarArticleFilter: SidebarArticleFilter
    let reloadID: UUID
}

private struct ArticleListSearchToolbarModifier: ViewModifier {
    let isEnabled: Bool
    @Binding var text: String

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .searchable(
                    text: $text,
                    placement: .toolbar,
                    prompt: ReadingLocalization.searchPrompt
                )
                .searchToolbarBehavior(.automatic)
        } else {
            content
        }
    }
}

private extension View {
    func applySearchableToolbar(isEnabled: Bool, text: Binding<String>) -> some View {
        modifier(ArticleListSearchToolbarModifier(isEnabled: isEnabled, text: text))
    }
}

// MARK: - Helpers

private struct ArticleListLoadContext: Hashable {
    let sidebarSelection: SidebarSelection?
    let sidebarArticleFilter: SidebarArticleFilter
    let normalizedSearchText: String
    let reloadID: UUID
}
