import SwiftUI

// MARK: - ArticleListView

struct ArticleListView: View {
    @Environment(\.appDependencies) private var dependencies
    @Environment(AppState.self) private var appState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.layoutDirection) private var layoutDirection

    let selectedSidebarSelection: SidebarSelection?
    let selectedSidebarArticleFilter: SidebarArticleFilter
    let reloadID: UUID
    let showsBackButton: Bool
    let navigateBackToSidebar: () -> Void
    let previewScreenState: ArticlesScreenState?

    @Binding var selection: UUID?
    @State private var controller: ArticlesScreenController
    @State private var searchText = ""
    @State private var refreshStartHapticTrigger = 0
    @State private var backNavigationContainerWidth: CGFloat = 0

    init(
        selectedSidebarSelection: SidebarSelection?,
        selectedSidebarArticleFilter: SidebarArticleFilter,
        reloadID: UUID,
        showsBackButton: Bool,
        navigateBackToSidebar: @escaping () -> Void,
        previewScreenState: ArticlesScreenState?,
        selection: Binding<UUID?>
    ) {
        self.selectedSidebarSelection = selectedSidebarSelection
        self.selectedSidebarArticleFilter = selectedSidebarArticleFilter
        self.reloadID = reloadID
        self.showsBackButton = showsBackButton
        self.navigateBackToSidebar = navigateBackToSidebar
        self.previewScreenState = previewScreenState
        self._selection = selection
        self._controller = State(initialValue: ArticlesScreenController(previewScreenState: previewScreenState))
    }

    // MARK: Body

    var body: some View {
        let derivedViewState = controller.screenState.derivedViewState(
            sidebarArticleFilter: selectedSidebarArticleFilter
        )

        ArticleListContentView(
            sections: derivedViewState.sections,
            visibleArticleIDs: derivedViewState.visibleArticles.map(\.id),
            customRefreshState: derivedViewState.customRefreshState,
            selection: $selection,
            scrollPositionID: articleListScrollPositionBinding,
            customRefreshPullProgressChanged: updateCustomRefreshPullProgress,
            customRefreshReleaseAction: triggerCustomRefresh,
            toggleReadStatusAction: toggleArticleReadStatus,
            toggleStarredAction: toggleStarredState
        )
        .toolbarTitleDisplayMode(.inline)
        .applySearchableToolbar(
            isEnabled: derivedViewState.toolbarActions.showsSearchAction,
            text: $searchText
        )
        .toolbar {
            ToolbarItem(placement: .title) {
                titleView(for: controller.screenState)
            }

            ToolbarItem(placement: .subtitle) {
                subtitleView(text: derivedViewState.navigationSubtitle)
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
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            backNavigationContainerWidth = newWidth
        }
        .simultaneousGesture(backNavigationGesture)
    }

    // MARK: Loading

    @MainActor
    private func loadArticles(
        retainsSessionFilterMutations: Bool = true,
        retainedSessionMembershipStatus: ArticleListEntryMembershipStatus = .retainedAfterFilterMutation,
        preservesRefreshFeedback: Bool = false
    ) async {
        let loadingSidebarSelection = selectedSidebarSelection
        let loadingSidebarArticleFilter = selectedSidebarArticleFilter

        await controller.load(
            selection: loadingSidebarSelection,
            sidebarArticleFilter: loadingSidebarArticleFilter,
            searchText: searchText,
            dependencies: dependencies,
            retainsSessionFilterMutations: retainsSessionFilterMutations,
            retainedSessionMembershipStatus: retainedSessionMembershipStatus,
            preservesRefreshFeedback: preservesRefreshFeedback
        )

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
            sidebarArticleFilter: selectedSidebarArticleFilter
        )
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
        controller.handleMarkAllAsReadAction(
            searchText: searchText,
            selection: selectedSidebarSelection,
            sidebarArticleFilter: selectedSidebarArticleFilter,
            dependencies: dependencies,
            isPreviewMode: isPreviewMode
        )
        let visibleArticleIDs = controller.visibleArticleIDs()
        selection = stabilizedSelection(availableArticleIDs: visibleArticleIDs)
        syncArticleNavigationContext(visibleArticleIDs)
    }

    // MARK: Bulk Actions

    @MainActor
    private func confirmMarkAllAsRead() {
        controller.confirmMarkAllAsRead(
            searchText: searchText,
            selection: selectedSidebarSelection,
            sidebarArticleFilter: selectedSidebarArticleFilter,
            dependencies: dependencies,
            isPreviewMode: isPreviewMode
        )
        let visibleArticleIDs = controller.visibleArticleIDs()
        selection = stabilizedSelection(availableArticleIDs: visibleArticleIDs)
        syncArticleNavigationContext(visibleArticleIDs)
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

    // MARK: Toolbar

    private var backNavigationGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                guard showsBackButton else { return }
                guard ReadingShellCompactNavigationState.shouldNavigateBackToSidebarOnDrag(
                    startLocationX: value.startLocation.x,
                    containerWidth: backNavigationContainerWidth,
                    layoutDirection: layoutDirection,
                    translation: value.translation
                ) else {
                    return
                }
                endCurrentArticleListSession()
                navigateBackToSidebar()
            }
    }

    @MainActor
    private func endCurrentArticleListSession() {
        appState.requestArticleListReload()
    }

    @MainActor
    private func applyArticleReadOnOpenEvent(_ event: ArticleReadOnOpenEvent?) {
        guard let event else { return }
        guard event.sidebarSelection == selectedSidebarSelection,
              event.sidebarArticleFilter == selectedSidebarArticleFilter else {
            return
        }

        controller.markArticleAsReadInCurrentSession(event.articleID)
        let visibleArticleIDs = controller.visibleArticleIDs()
        selection = stabilizedSelection(availableArticleIDs: visibleArticleIDs)
        syncArticleNavigationContext(visibleArticleIDs)
    }

    @ViewBuilder
    private func titleView(for screenState: ArticlesScreenState) -> some View {
        Text(screenState.navigationTitle)
            .font(.title3.weight(.semibold))
    }

    @ViewBuilder
    private func subtitleView(text: String) -> some View {
        if text.isEmpty == false {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
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
            preservesRefreshFeedback: preservesRefreshFeedback
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
