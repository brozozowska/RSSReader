import SwiftUI

// MARK: - ArticleListView

struct ArticleListView: View {
    @Environment(\.appDependencies) private var dependencies
    @Environment(AppState.self) private var appState

    let selectedSidebarSelection: SidebarSelection?
    let selectedSourcesFilter: SourcesFilter
    let reloadID: UUID
    let showsBackButton: Bool
    let navigateBackToSources: () -> Void
    let previewScreenState: ArticlesScreenState?

    @Binding var selection: UUID?
    @State private var controller: ArticlesScreenController
    @State private var searchText = ""

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
        let derivedViewState = controller.screenState.derivedViewState(searchText: searchText)

        ArticleListContentView(
            sections: derivedViewState.sections,
            selection: $selection,
            refreshAction: refreshCurrentSelection,
            markAsReadAction: markArticleAsRead,
            toggleStarredAction: toggleStarredState
        )
        .toolbarTitleDisplayMode(.inline)
        .searchable(
            text: $searchText,
            placement: .toolbar,
            prompt: "Search Articles"
        )
        .searchToolbarBehavior(.automatic)
        .toolbar {
            if showsBackButton {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: navigateBackToSources) {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel("Back to Sources")
                }
            }

            ToolbarItem(placement: .title) {
                titleView(for: controller.screenState)
            }

            ToolbarItem(placement: .subtitle) {
                subtitleView(for: controller.screenState)
            }

            if derivedViewState.toolbarActions.showsMarkAllAsReadAction {
                ToolbarItem(placement: .bottomBar) {
                    Button(action: presentMarkAllAsReadConfirmation) {
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
            await loadArticles()
        }
        .onChange(of: searchText) { _, _ in
            selection = stabilizedSelection(
                availableArticleIDs: controller.screenState
                    .derivedViewState(searchText: searchText)
                    .visibleArticles
                    .map(\.id)
            )
        }
        .simultaneousGesture(backNavigationGesture)
    }

    // MARK: Loading

    @MainActor
    private func loadArticles() async {
        if controller.shouldResetArticleSelection(for: selectedSidebarSelection) {
            selection = nil
        }

        await controller.load(
            selection: selectedSidebarSelection,
            sourcesFilter: selectedSourcesFilter,
            dependencies: dependencies
        )

        selection = stabilizedSelection(
            availableArticleIDs: controller.screenState
                .derivedViewState(searchText: searchText)
                .visibleArticles
                .map(\.id)
        )
    }

    // MARK: Selection

    private func stabilizedSelection(availableArticleIDs: [UUID]) -> UUID? {
        if let selection, availableArticleIDs.contains(selection) {
            return selection
        }
        return availableArticleIDs.first
    }

    private func currentArticleListFilter() -> ArticleListFilter {
        ArticlesScreenMutationReducer.articleListFilter(
            selection: selectedSidebarSelection,
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
    private func presentMarkAllAsReadConfirmation() {
        controller.screenState.presentMarkAllAsReadConfirmation()
    }

    // MARK: Bulk Actions

    @MainActor
    private func confirmMarkAllAsRead() {
        let visibleArticles = controller.screenState
            .derivedViewState(searchText: searchText)
            .visibleArticles

        if isPreviewMode == false {
            guard let articleStateService = dependencies.articleStateService else {
                dependencies.logger.error("Article state service is unavailable for mark all as read action")
                controller.screenState.dismissConfirmation()
                return
            }

            do {
                _ = try articleStateService.markAllVisibleAsRead(visibleArticles, at: .now)
            } catch {
                dependencies.logger.error("Failed to mark all visible articles as read: \(error)")
                controller.screenState.dismissConfirmation()
                return
            }
        }

        let updatedArticles = ArticlesScreenMutationReducer.reduceAfterMarkAllAsRead(
            visibleArticles: visibleArticles,
            allArticles: controller.screenState.articles,
            filter: currentArticleListFilter()
        )
        controller.screenState.applyMarkAllAsRead(
            updatedArticles,
            navigationSubtitle: ArticlesScreenSubtitleResolver.resolve(
                articles: updatedArticles,
                sourcesFilter: selectedSourcesFilter
            )
        )
        selection = stabilizedSelection(
            availableArticleIDs: controller.screenState
                .derivedViewState(searchText: searchText)
                .visibleArticles
                .map(\.id)
        )
    }

    // MARK: Row Actions

    @MainActor
    private func markArticleAsRead(_ article: ArticleListItemDTO) {
        guard article.isRead == false else { return }

        if isPreviewMode == false {
            guard let articleStateService = dependencies.articleStateService else {
                dependencies.logger.error("Article state service is unavailable for mark as read action")
                return
            }

            do {
                _ = try articleStateService.markAsRead(
                    feedID: article.feedID,
                    articleExternalID: article.articleExternalID,
                    at: .now
                )
            } catch {
                dependencies.logger.error("Failed to mark article as read: \(error)")
                return
            }
        }

        let mutation = ArticlesScreenMutationReducer.mutationAfterMarkAsRead(
            article: article,
            filter: currentArticleListFilter()
        )
        applyArticleRowMutation(mutation, for: article.id)
    }

    @MainActor
    private func toggleStarredState(for article: ArticleListItemDTO) {
        if isPreviewMode == false {
            guard let articleStateService = dependencies.articleStateService else {
                dependencies.logger.error("Article state service is unavailable for star action")
                return
            }

            do {
                _ = try articleStateService.toggleStarred(
                    feedID: article.feedID,
                    articleExternalID: article.articleExternalID,
                    at: .now
                )
            } catch {
                dependencies.logger.error("Failed to toggle starred state for article: \(error)")
                return
            }
        }

        let mutation = ArticlesScreenMutationReducer.mutationAfterToggleStarred(
            article: article,
            filter: currentArticleListFilter()
        )
        applyArticleRowMutation(mutation, for: article.id)
    }

    @MainActor
    private func applyArticleRowMutation(_ mutation: ArticleRowMutation, for articleID: UUID) {
        let updatedArticles = ArticlesScreenMutationReducer.apply(
            mutation,
            articleID: articleID,
            allArticles: controller.screenState.articles
        )
        controller.screenState.applyArticleRowMutation(
            articleID: articleID,
            mutation: mutation,
            navigationSubtitle: ArticlesScreenSubtitleResolver.resolve(
                articles: updatedArticles,
                sourcesFilter: selectedSourcesFilter
            )
        )
        selection = stabilizedSelection(
            availableArticleIDs: controller.screenState
                .derivedViewState(searchText: searchText)
                .visibleArticles
                .map(\.id)
        )
    }

    // MARK: Toolbar

    private var backNavigationGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                guard showsBackButton else { return }
                guard ArticlesScreenNavigationState.shouldNavigateBackOnDrag(
                    startLocationX: value.startLocation.x,
                    translation: value.translation
                ) else {
                    return
                }
                navigateBackToSources()
            }
    }

    @ViewBuilder
    private func titleView(for screenState: ArticlesScreenState) -> some View {
        Text(screenState.navigationTitle)
            .font(.title3.weight(.semibold))
    }

    @ViewBuilder
    private func subtitleView(for screenState: ArticlesScreenState) -> some View {
        if screenState.navigationSubtitle.isEmpty == false {
            Text(screenState.navigationSubtitle)
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
            primaryLoadingOverlay(loadingState)
        } else if let placeholder = derivedViewState.searchPlaceholder {
            ContentUnavailableView(
                placeholder.title,
                systemImage: placeholder.systemImage,
                description: placeholder.description.map(Text.init)
            )
        } else if let primaryFailureMessage = controller.screenState.primaryFailureMessage {
            ContentUnavailableView {
                Label("Unable to Load Articles", systemImage: "exclamationmark.triangle")
            } description: {
                Text(primaryFailureMessage)
            } actions: {
                Button("Retry") {
                    retryPrimaryLoad()
                }
            }
        } else if let placeholder = controller.screenState.placeholder {
            ContentUnavailableView(
                placeholder.title,
                systemImage: placeholder.systemImage,
                description: placeholder.description.map(Text.init)
            )
        }
    }

    private func primaryLoadingOverlay(_ loadingState: ArticlesScreenPrimaryLoadingState) -> some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)

            Text(loadingState.title)
                .font(.headline)

            Text(loadingState.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func retryPrimaryLoad() {
        Task {
            await loadArticles()
        }
    }

    // MARK: Refresh

    @MainActor
    private func refreshCurrentSelection() async {
        guard isPreviewMode == false else { return }
        await controller.refreshCurrentSelection(
            selection: selectedSidebarSelection,
            dependencies: dependencies,
            appState: appState
        )
    }

    @MainActor
    private func dismissRefreshFeedback() {
        controller.screenState.dismissRefreshFeedback()
    }
}

// MARK: - Helpers

private struct ArticleListLoadContext: Hashable {
    let sourceSelection: SidebarSelection?
    let sourcesFilter: SourcesFilter
    let reloadID: UUID
}

enum SourcesFilterArticleListFilterResolver {
    static func resolve(for sourcesFilter: SourcesFilter) -> ArticleListFilter {
        switch sourcesFilter {
        case .allItems:
            .all
        case .unread:
            .unread
        case .starred:
            .starred
        }
    }
}

extension ArticleListItemDTO {
    func updating(isRead: Bool, isStarred: Bool) -> ArticleListItemDTO {
        ArticleListItemDTO(
            id: id,
            feedID: feedID,
            feedTitle: feedTitle,
            articleExternalID: articleExternalID,
            title: title,
            summary: summary,
            author: author,
            publishedAt: publishedAt,
            fetchedAt: fetchedAt,
            isRead: isRead,
            isStarred: isStarred,
            isHidden: isHidden
        )
    }
}
