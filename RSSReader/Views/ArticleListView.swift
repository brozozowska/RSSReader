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
        let visibleArticles = filteredArticles(from: controller.screenState.articles)
        let visibleSections = ArticlesDaySectionsBuilder.build(from: visibleArticles)
        let toolbarActions = ArticlesScreenToolbarActionsState(
            selection: controller.screenState.selection,
            visibleArticles: visibleArticles
        )

        ArticleListContentView(
            sections: visibleSections,
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

            if toolbarActions.showsMarkAllAsReadAction {
                ToolbarItem(placement: .bottomBar) {
                    Button(action: presentMarkAllAsReadConfirmation) {
                        Image(systemName: "checkmark.circle.fill")
                    }
                    .disabled(toolbarActions.isMarkAllAsReadEnabled == false)
                    .accessibilityLabel("Mark all as read")
                }
            }

            if toolbarActions.showsMarkAllAsReadAction
                && toolbarActions.showsSearchAction {
                ToolbarSpacer(placement: .bottomBar)
            }

            if toolbarActions.showsSearchAction {
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
            overlayContent(for: visibleArticles)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            ArticleListRefreshBanner(
                isRefreshing: controller.screenState.showsRefreshActivityIndicator,
                feedbackMessage: controller.screenState.refreshFeedback?.message,
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
                availableArticleIDs: filteredArticles(from: controller.screenState.articles).map(\.id)
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
            availableArticleIDs: filteredArticles(from: controller.screenState.articles).map(\.id)
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
        switch selectedSidebarSelection {
        case .unread:
            .unread
        case .starred:
            .starred
        case .inbox, .folder, .feed, .none:
            SourcesFilterArticleListFilterResolver.resolve(for: selectedSourcesFilter)
        }
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
        let visibleArticles = filteredArticles(from: controller.screenState.articles)

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

        let updatedArticles = makeArticlesAfterMarkAllAsRead(
            visibleArticles: visibleArticles,
            allArticles: controller.screenState.articles
        )
        controller.screenState.applyMarkAllAsRead(
            updatedArticles,
            navigationSubtitle: ArticlesScreenSubtitleResolver.resolve(
                articles: updatedArticles,
                sourcesFilter: selectedSourcesFilter
            )
        )
        selection = stabilizedSelection(
            availableArticleIDs: filteredArticles(from: updatedArticles).map(\.id)
        )
    }

    private func makeArticlesAfterMarkAllAsRead(
        visibleArticles: [ArticleListItemDTO],
        allArticles: [ArticleListItemDTO]
    ) -> [ArticleListItemDTO] {
        let visibleArticleIDs = Set(visibleArticles.map(\.id))

        guard currentArticleListFilter() != .unread else {
            return allArticles.filter { visibleArticleIDs.contains($0.id) == false }
        }

        return allArticles.map { article in
            guard visibleArticleIDs.contains(article.id) else {
                return article
            }

            return article.updating(
                isRead: true,
                isStarred: article.isStarred
            )
        }
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

        let mutation = articleRowMutationAfterMarkAsRead(article)
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

        let mutation = articleRowMutationAfterToggleStarred(article)
        applyArticleRowMutation(mutation, for: article.id)
    }

    @MainActor
    private func applyArticleRowMutation(_ mutation: ArticleRowMutation, for articleID: UUID) {
        let updatedArticles = makeArticlesAfterApplyingArticleRowMutation(
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
            availableArticleIDs: filteredArticles(from: updatedArticles).map(\.id)
        )
    }

    private func articleRowMutationAfterMarkAsRead(_ article: ArticleListItemDTO) -> ArticleRowMutation {
        if currentArticleListFilter() == .unread {
            return .remove
        }

        return .update(
            article.updating(
                isRead: true,
                isStarred: article.isStarred
            )
        )
    }

    private func articleRowMutationAfterToggleStarred(_ article: ArticleListItemDTO) -> ArticleRowMutation {
        let updatedIsStarred = article.isStarred == false

        if currentArticleListFilter() == .starred && updatedIsStarred == false {
            return .remove
        }

        return .update(
            article.updating(
                isRead: article.isRead,
                isStarred: updatedIsStarred
            )
        )
    }

    private func makeArticlesAfterApplyingArticleRowMutation(
        _ mutation: ArticleRowMutation,
        articleID: UUID,
        allArticles: [ArticleListItemDTO]
    ) -> [ArticleListItemDTO] {
        switch mutation {
        case .update(let updatedArticle):
            allArticles.map { article in
                article.id == articleID ? updatedArticle : article
            }
        case .remove:
            allArticles.filter { $0.id != articleID }
        }
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

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func filteredArticles(from articles: [ArticleListItemDTO]) -> [ArticleListItemDTO] {
        guard normalizedSearchText.isEmpty == false else {
            return articles
        }

        return articles.filter { article in
            [article.feedTitle, article.title, article.summary, article.author]
                .compactMap { $0 }
                .contains { $0.localizedCaseInsensitiveContains(normalizedSearchText) }
        }
    }

    private func searchPlaceholder(for visibleArticles: [ArticleListItemDTO]) -> ArticlesScreenPlaceholderState? {
        guard normalizedSearchText.isEmpty == false else {
            return nil
        }

        guard controller.screenState.phase == .loaded || controller.screenState.phase == .empty else {
            return nil
        }

        guard visibleArticles.isEmpty else {
            return nil
        }

        return ArticlesScreenPlaceholderState(
            title: "No Search Results",
            systemImage: "magnifyingglass",
            description: "No visible articles match \"\(normalizedSearchText)\"."
        )
    }

    @ViewBuilder
    private func overlayContent(for visibleArticles: [ArticleListItemDTO]) -> some View {
        if controller.screenState.showsPrimaryLoadingIndicator {
            primaryLoadingOverlay
        } else if let placeholder = searchPlaceholder(for: visibleArticles) {
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

    private var primaryLoadingOverlay: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)

            Text("Loading Articles")
                .font(.headline)

            Text(primaryLoadingDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var primaryLoadingDescription: String {
        switch selectedSidebarSelection {
        case .none:
            "Select Inbox or a source to start reading."
        case .inbox:
            "Fetching the latest articles for your current inbox selection."
        case .unread:
            "Fetching unread articles across your current sources."
        case .starred:
            "Fetching the articles you marked as starred."
        case .folder(let folderName):
            "Fetching articles for \(folderName)."
        case .feed:
            "Fetching articles for the current source."
        }
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

private extension ArticleListItemDTO {
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
