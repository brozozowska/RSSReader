import SwiftUI

// MARK: - ArticleListView

struct ArticleListView: View {
    @Environment(\.appDependencies) private var dependencies
    @Environment(AppState.self) private var appState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let selectedSidebarSelection: SidebarSelection?
    let selectedSourcesFilter: SourcesFilter
    let reloadID: UUID
    let showsBackButton: Bool
    let navigateBackToSources: () -> Void
    let previewScreenState: ArticlesScreenState?

    @Binding var selection: UUID?
    @State private var controller: ArticlesScreenController
    @State private var searchText = ""
    @State private var articleListIdentity = UUID()
    @State private var deferredSessionReloadTask: Task<Void, Never>?
    @State private var refreshStartHapticTrigger = 0

    init(
        selectedSidebarSelection: SidebarSelection?,
        selectedSourcesFilter: SourcesFilter,
        reloadID: UUID,
        showsBackButton: Bool,
        navigateBackToSources: @escaping () -> Void,
        previewScreenState: ArticlesScreenState?,
        selection: Binding<UUID?>
    ) {
        self.selectedSidebarSelection = selectedSidebarSelection
        self.selectedSourcesFilter = selectedSourcesFilter
        self.reloadID = reloadID
        self.showsBackButton = showsBackButton
        self.navigateBackToSources = navigateBackToSources
        self.previewScreenState = previewScreenState
        self._selection = selection
        self._controller = State(initialValue: ArticlesScreenController(previewScreenState: previewScreenState))
    }

    // MARK: Body

    var body: some View {
        let sessionReadArticleIDs = appState.currentArticleListSessionReadArticleIDs(
            sourceSelection: selectedSidebarSelection,
            sourcesFilter: selectedSourcesFilter
        )
        let derivedViewState = controller.screenState.derivedViewState(
            searchText: searchText,
            sourcesFilter: selectedSourcesFilter,
            sessionReadArticleIDs: sessionReadArticleIDs
        )

        ArticleListContentView(
            sections: derivedViewState.sections,
            visibleArticleIDs: derivedViewState.visibleArticles.map(\.id),
            listIdentity: articleListIdentity,
            selection: $selection,
            refreshAction: refreshCurrentSelection,
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
                    .accessibilityLabel("Mark all as read")
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
            "Mark all as read?",
            isPresented: markAllAsReadConfirmationIsPresented
        ) {
            Button("Mark all as read", role: .destructive, action: confirmMarkAllAsRead)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action will mark all visible articles as read.")
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
            sourceSelection: selectedSidebarSelection,
            sourcesFilter: selectedSourcesFilter,
            reloadID: reloadID
        )) {
            guard isPreviewMode == false else { return }
            await loadArticles(
                retainsSessionReadArticles: true,
                recreatesListAfterSessionRetention: true
            )
        }
        .onChange(of: searchText) { _, _ in
            let visibleArticleIDs = controller.visibleArticleIDs(searchText: searchText)
            selection = stabilizedSelection(availableArticleIDs: visibleArticleIDs)
            syncArticleNavigationContext(visibleArticleIDs)
        }
        .onChange(of: appState.articleListSessionReadArticleIDs) { _, _ in
            syncSelectionAfterSessionReadPresentationChange()
        }
        .onChange(of: appState.selectedArticleID) { oldValue, newValue in
            if oldValue != nil && newValue == nil {
                resetArticleListIdentity()
            }
        }
        .sensoryFeedback(
            .impact(flexibility: .solid, intensity: 0.65),
            trigger: refreshStartHapticTrigger
        )
        .simultaneousGesture(backNavigationGesture)
    }

    // MARK: Loading

    @MainActor
    private func loadArticles(
        retainsSessionReadArticles: Bool = true,
        recreatesListAfterSessionRetention: Bool = false
    ) async {
        let loadingSidebarSelection = selectedSidebarSelection
        let loadingSourcesFilter = selectedSourcesFilter
        let sessionReadArticleIDs = appState.currentArticleListSessionReadArticleIDs(
            sourceSelection: loadingSidebarSelection,
            sourcesFilter: loadingSourcesFilter
        )

        await controller.load(
            selection: loadingSidebarSelection,
            sourcesFilter: loadingSourcesFilter,
            dependencies: dependencies,
            sessionReadArticleIDs: sessionReadArticleIDs,
            retainsSessionReadArticles: retainsSessionReadArticles
        )

        guard loadingSidebarSelection == appState.selectedSidebarSelection,
              loadingSourcesFilter == appState.selectedSourcesFilter else {
            return
        }

        let visibleArticleIDs = controller.visibleArticleIDs(searchText: searchText)
        selection = stabilizedSelection(availableArticleIDs: visibleArticleIDs)
        syncArticleNavigationContext(visibleArticleIDs)

        if recreatesListAfterSessionRetention,
           retainsSessionReadArticles,
           sessionReadArticleIDs.isEmpty == false {
            resetArticleListIdentity()
        }
    }

    @MainActor
    private func syncSelectionAfterSessionReadPresentationChange() {
        let visibleArticleIDs = controller.visibleArticleIDs(searchText: searchText)
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
        appState.updateArticleNavigationContext(
            visibleArticleIDs,
            sourceSelection: selectedSidebarSelection,
            sourcesFilter: selectedSourcesFilter
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
            sourcesFilter: selectedSourcesFilter,
            dependencies: dependencies,
            isPreviewMode: isPreviewMode
        )
        let visibleArticleIDs = controller.visibleArticleIDs(searchText: searchText)
        selection = stabilizedSelection(availableArticleIDs: visibleArticleIDs)
        syncArticleNavigationContext(visibleArticleIDs)
    }

    // MARK: Bulk Actions

    @MainActor
    private func confirmMarkAllAsRead() {
        controller.confirmMarkAllAsRead(
            searchText: searchText,
            selection: selectedSidebarSelection,
            sourcesFilter: selectedSourcesFilter,
            dependencies: dependencies,
            isPreviewMode: isPreviewMode
        )
        let visibleArticleIDs = controller.visibleArticleIDs(searchText: searchText)
        selection = stabilizedSelection(availableArticleIDs: visibleArticleIDs)
        syncArticleNavigationContext(visibleArticleIDs)
    }

    // MARK: Row Actions

    @MainActor
    private func toggleArticleReadStatus(_ article: ArticleListItemDTO) {
        controller.toggleArticleReadStatus(
            article,
            selection: selectedSidebarSelection,
            sourcesFilter: selectedSourcesFilter,
            dependencies: dependencies,
            isPreviewMode: isPreviewMode
        )
        let visibleArticleIDs = controller.visibleArticleIDs(searchText: searchText)
        selection = stabilizedSelection(availableArticleIDs: visibleArticleIDs)
        syncArticleNavigationContext(visibleArticleIDs)
    }

    @MainActor
    private func toggleStarredState(for article: ArticleListItemDTO) {
        controller.toggleStarredState(
            for: article,
            selection: selectedSidebarSelection,
            sourcesFilter: selectedSourcesFilter,
            dependencies: dependencies,
            isPreviewMode: isPreviewMode
        )
        let visibleArticleIDs = controller.visibleArticleIDs(searchText: searchText)
        selection = stabilizedSelection(availableArticleIDs: visibleArticleIDs)
        syncArticleNavigationContext(visibleArticleIDs)
    }

    // MARK: Toolbar

    private var backNavigationGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                guard showsBackButton else { return }
                guard ReadingShellCompactNavigationState.shouldNavigateBackToSourcesOnDrag(
                    startLocationX: value.startLocation.x,
                    translation: value.translation
                ) else {
                    return
                }
                endCurrentArticleListSession()
                navigateBackToSources()
            }
    }

    @MainActor
    private func endCurrentArticleListSession() {
        appState.clearArticleListSessionReadArticles()
        appState.requestArticleListReload()
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
                title: "Unable to Load Articles",
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
            await loadArticles(retainsSessionReadArticles: true)
        }
    }

    // MARK: Refresh

    @MainActor
    private func refreshCurrentSelection() async {
        guard isPreviewMode == false else { return }

        refreshStartHapticTrigger += 1
        deferredSessionReloadTask?.cancel()
        deferredSessionReloadTask = nil

        let sessionReadArticleIDs = appState.currentArticleListSessionReadArticleIDs(
            sourceSelection: selectedSidebarSelection,
            sourcesFilter: selectedSourcesFilter
        )

        await controller.refreshCurrentSelection(
            selection: selectedSidebarSelection,
            dependencies: dependencies,
            appState: appState,
            requestsArticleListReload: false
        )

        await loadArticles(retainsSessionReadArticles: sessionReadArticleIDs.isEmpty == false)

        if sessionReadArticleIDs.isEmpty == false {
            scheduleDeferredSessionReload()
        }
    }

    private func scheduleDeferredSessionReload() {
        let deferredSelection = selectedSidebarSelection
        let deferredSourcesFilter = selectedSourcesFilter

        deferredSessionReloadTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: ArticleListDeferredSessionReload.delayNanoseconds)
            guard Task.isCancelled == false else { return }
            guard deferredSelection == appState.selectedSidebarSelection,
                  deferredSourcesFilter == appState.selectedSourcesFilter else {
                return
            }

            appState.clearArticleListSessionReadArticles()
            await loadArticles(retainsSessionReadArticles: false)
            await scheduleListIdentityResetAfterAnimation()
        }
    }

    private func scheduleListIdentityResetAfterAnimation() async {
        try? await Task.sleep(nanoseconds: ArticleListDeferredSessionReload.identityResetDelayNanoseconds)
        guard Task.isCancelled == false else { return }
        resetArticleListIdentity()
    }

    private func resetArticleListIdentity() {
        articleListIdentity = UUID()
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
                    prompt: "Search Articles"
                )
                .searchToolbarBehavior(.automatic)
        } else {
            content
        }
    }
}

private enum ArticleListDeferredSessionReload {
    static let delayMilliseconds = 180
    static let delayNanoseconds: UInt64 = UInt64(delayMilliseconds) * 1_000_000
    static let identityResetDelayMilliseconds = 320
    static let identityResetDelayNanoseconds: UInt64 = UInt64(identityResetDelayMilliseconds) * 1_000_000
}

private extension View {
    func applySearchableToolbar(isEnabled: Bool, text: Binding<String>) -> some View {
        modifier(ArticleListSearchToolbarModifier(isEnabled: isEnabled, text: text))
    }
}

// MARK: - Helpers

private struct ArticleListLoadContext: Hashable {
    let sourceSelection: SidebarSelection?
    let sourcesFilter: SourcesFilter
    let reloadID: UUID
}
