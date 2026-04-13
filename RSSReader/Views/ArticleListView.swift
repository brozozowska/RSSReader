import SwiftUI

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
    @State private var screenState = ArticlesScreenState()
    @State private var lastLoadedSourceSelection: SidebarSelection? = nil
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
        self._screenState = State(initialValue: previewScreenState ?? ArticlesScreenState())
        self._lastLoadedSourceSelection = State(initialValue: previewScreenState?.selection)
    }

    var body: some View {
        let visibleArticles = filteredArticles(from: screenState.articles)
        let visibleSections = ArticlesDaySectionsBuilder.build(from: visibleArticles)
        let toolbarActions = ArticlesScreenToolbarActionsState(
            selection: screenState.selection,
            visibleArticles: visibleArticles
        )

        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            List(selection: $selection) {
                ForEach(visibleSections) { section in
                    Section {
                        ForEach(section.articles, id: \.id) { article in
                            ArticleListRowView(article: article)
                                .tag(article.id)
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    leadingSwipeActions(for: article)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    trailingSwipeActions(for: article)
                                }
                                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }
                    } header: {
                        ArticleListSectionHeaderView(title: section.title)
                    }
                    .textCase(nil)
                }
            }
            .listStyle(.plain)
            .listSectionSpacing(12)
            .scrollContentBackground(.hidden)
            .contentMargins(.top, 8, for: .scrollContent)
            .refreshable {
                await refreshCurrentSelection()
            }
        }
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
                titleView(for: screenState)
            }

            ToolbarItem(placement: .subtitle) {
                subtitleView(for: screenState)
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
            isPresented: markAllAsReadConfirmationIsPresented,
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
            refreshStatusBanner
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
                availableArticleIDs: filteredArticles(from: screenState.articles).map(\.id)
            )
        }
        .simultaneousGesture(backNavigationGesture)
    }

    @MainActor
    private func loadArticles() async {
        let sourceSelectionChanged = lastLoadedSourceSelection != selectedSidebarSelection
        let navigationTitle = resolveNavigationTitle()
        let loadingSubtitle = resolveNavigationSubtitle(for: screenState.articles)
        screenState.beginLoading(
            for: selectedSidebarSelection,
            navigationTitle: navigationTitle,
            navigationSubtitle: loadingSubtitle,
            resetsContent: sourceSelectionChanged
        )

        if sourceSelectionChanged {
            selection = nil
        }
        defer {
            lastLoadedSourceSelection = selectedSidebarSelection
        }

        guard let articleQueryService = dependencies.articleQueryService else {
            screenState.applyLoadingFailure(
                "Article query service is unavailable.",
                selection: selectedSidebarSelection,
                navigationTitle: navigationTitle,
                navigationSubtitle: loadingSubtitle,
                retainsContent: false
            )
            selection = nil
            return
        }

        let sortMode = await loadSortMode()

        do {
            let loadedArticles: [ArticleListItemDTO]
            switch selectedSidebarSelection {
            case .inbox:
                loadedArticles = try articleQueryService.fetchInboxListItems(
                    sortMode: sortMode,
                    filter: SourcesFilterArticleListFilterResolver.resolve(for: selectedSourcesFilter)
                )
            case .unread:
                loadedArticles = try articleQueryService.fetchInboxListItems(
                    sortMode: sortMode,
                    filter: .unread
                )
            case .starred:
                loadedArticles = try articleQueryService.fetchInboxListItems(
                    sortMode: sortMode,
                    filter: .starred
                )
            case .folder(let folderName):
                loadedArticles = try articleQueryService.fetchFolderListItems(
                    folderName: folderName,
                    sortMode: sortMode,
                    filter: SourcesFilterArticleListFilterResolver.resolve(for: selectedSourcesFilter)
                )
            case .feed(let selectedFeedID):
                loadedArticles = try articleQueryService.fetchArticleListItems(
                    feedID: selectedFeedID,
                    sortMode: sortMode,
                    filter: SourcesFilterArticleListFilterResolver.resolve(for: selectedSourcesFilter)
                )
            case .none:
                loadedArticles = []
            }

            screenState.applyLoadedArticles(
                loadedArticles,
                selection: selectedSidebarSelection,
                navigationTitle: navigationTitle,
                navigationSubtitle: resolveNavigationSubtitle(for: loadedArticles)
            )
        } catch {
            dependencies.logger.error("Failed to load article list for selection \(String(describing: selectedSidebarSelection)): \(error)")
            screenState.applyLoadingFailure(
                error.localizedDescription,
                selection: selectedSidebarSelection,
                navigationTitle: navigationTitle,
                navigationSubtitle: loadingSubtitle,
                retainsContent: sourceSelectionChanged == false
            )
        }

        self.selection = stabilizedSelection(
            availableArticleIDs: filteredArticles(from: screenState.articles).map(\.id)
        )
    }

    private func stabilizedSelection(availableArticleIDs: [UUID]) -> UUID? {
        if let selection, availableArticleIDs.contains(selection) {
            return selection
        }
        return availableArticleIDs.first
    }

    @MainActor
    private func resolveNavigationTitle() -> String {
        let selectedFeedTitle: String?
        if case .feed(let feedID) = selectedSidebarSelection {
            selectedFeedTitle = try? dependencies.feedRepository?.fetchFeed(id: feedID)?.title
        } else {
            selectedFeedTitle = nil
        }

        return ArticlesScreenNavigationTitleResolver.resolve(
            selection: selectedSidebarSelection,
            selectedFeedTitle: selectedFeedTitle
        )
    }

    private func resolveNavigationSubtitle(for articles: [ArticleListItemDTO]) -> String {
        ArticlesScreenSubtitleResolver.resolve(
            articles: articles,
            sourcesFilter: selectedSourcesFilter
        )
    }

    private var markAllAsReadConfirmationIsPresented: Binding<Bool> {
        Binding(
            get: { screenState.pendingConfirmation == .markAllAsRead },
            set: { isPresented in
                if isPresented == false {
                    screenState.dismissConfirmation()
                }
            }
        )
    }

    @MainActor
    private func presentMarkAllAsReadConfirmation() {
        screenState.presentMarkAllAsReadConfirmation()
    }

    @MainActor
    private func confirmMarkAllAsRead() {
        let visibleArticles = filteredArticles(from: screenState.articles)

        if isPreviewMode == false {
            guard let articleStateService = dependencies.articleStateService else {
                dependencies.logger.error("Article state service is unavailable for mark all as read action")
                screenState.dismissConfirmation()
                return
            }

            do {
                _ = try articleStateService.markAllVisibleAsRead(visibleArticles, at: .now)
            } catch {
                dependencies.logger.error("Failed to mark all visible articles as read: \(error)")
                screenState.dismissConfirmation()
                return
            }
        }

        let updatedArticles = makeArticlesAfterMarkAllAsRead(
            visibleArticles: visibleArticles,
            allArticles: screenState.articles
        )
        screenState.applyMarkAllAsRead(
            updatedArticles,
            navigationSubtitle: resolveNavigationSubtitle(for: updatedArticles)
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

            return ArticleListItemDTO(
                id: article.id,
                feedID: article.feedID,
                feedTitle: article.feedTitle,
                articleExternalID: article.articleExternalID,
                title: article.title,
                summary: article.summary,
                author: article.author,
                publishedAt: article.publishedAt,
                fetchedAt: article.fetchedAt,
                isRead: true,
                isStarred: article.isStarred,
                isHidden: article.isHidden
            )
        }
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

    @ViewBuilder
    private func leadingSwipeActions(for article: ArticleListItemDTO) -> some View {
        let swipeActionsState = ArticleRowSwipeActionsState(article: article)

        if swipeActionsState.canMarkAsRead {
            Button {
                markArticleAsRead(article)
            } label: {
                Label("Read", systemImage: "checkmark.circle.fill")
            }
            .tint(.green)
        }
    }

    @ViewBuilder
    private func trailingSwipeActions(for article: ArticleListItemDTO) -> some View {
        let swipeActionsState = ArticleRowSwipeActionsState(article: article)

        Button {
            toggleStarredState(for: article)
        } label: {
            Label(swipeActionsState.starActionTitle, systemImage: swipeActionsState.starActionSystemImage)
        }
        .tint(.yellow)
    }

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
            allArticles: screenState.articles
        )
        screenState.applyArticleRowMutation(
            articleID: articleID,
            mutation: mutation,
            navigationSubtitle: resolveNavigationSubtitle(for: updatedArticles)
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

    @MainActor
    private func loadSortMode() async -> ArticleSortMode {
        guard let appSettingsRepository = dependencies.appSettingsRepository else {
            return .publishedAtDescending
        }

        do {
            return try appSettingsRepository.fetchOrCreate().sortMode
        } catch {
            dependencies.logger.error("Failed to load app settings for article sort mode: \(error)")
            return .publishedAtDescending
        }
    }

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

        guard screenState.phase == .loaded || screenState.phase == .empty else {
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
        if screenState.showsPrimaryLoadingIndicator {
            primaryLoadingOverlay
        } else if let placeholder = searchPlaceholder(for: visibleArticles) {
            ContentUnavailableView(
                placeholder.title,
                systemImage: placeholder.systemImage,
                description: placeholder.description.map(Text.init)
            )
        } else if let primaryFailureMessage = screenState.primaryFailureMessage {
            ContentUnavailableView {
                Label("Unable to Load Articles", systemImage: "exclamationmark.triangle")
            } description: {
                Text(primaryFailureMessage)
            } actions: {
                Button("Retry") {
                    retryPrimaryLoad()
                }
            }
        } else if let placeholder = screenState.placeholder {
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

    @ViewBuilder
    private var refreshStatusBanner: some View {
        if screenState.showsRefreshActivityIndicator {
            refreshBanner(
                title: "Refreshing Articles",
                message: "Updating the current selection."
            )
        } else if let refreshFeedback = screenState.refreshFeedback {
            refreshBanner(
                title: "Refresh Failed",
                message: refreshFeedback.message,
                showsRetryAction: true
            )
        }
    }

    private func refreshBanner(
        title: String,
        message: String,
        showsRetryAction: Bool = false
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            if screenState.showsRefreshActivityIndicator {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            if showsRetryAction {
                Button("Retry") {
                    Task {
                        await refreshCurrentSelection()
                    }
                }
                .font(.footnote.weight(.semibold))

                Button {
                    dismissRefreshFeedback()
                } label: {
                    Image(systemName: "xmark")
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityLabel("Dismiss refresh error")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private func retryPrimaryLoad() {
        Task {
            await loadArticles()
        }
    }

    @MainActor
    private func refreshCurrentSelection() async {
        guard isPreviewMode == false else { return }
        screenState.dismissRefreshFeedback()
        let result = await dependencies.refreshCurrentSelection(using: appState)

        if let result {
            if let refreshFailureMessage = refreshFailureMessage(for: result) {
                screenState.presentRefreshFailure(refreshFailureMessage)
            }
        } else if selectedSidebarSelection != nil {
            screenState.presentRefreshFailure("Unable to refresh the current selection right now.")
        }
    }

    @MainActor
    private func dismissRefreshFeedback() {
        screenState.dismissRefreshFeedback()
    }

    private func refreshFailureMessage(for result: FeedRefreshBatchResult) -> String? {
        guard result.summary.failedCount > 0 else {
            return nil
        }

        if let firstError = result.failureDescriptions.first {
            if result.summary.failedCount == 1 {
                return firstError
            }
            return "\(result.summary.failedCount) sources failed to refresh. First error: \(firstError)"
        }

        if result.summary.failedCount == 1 {
            return "The current source failed to refresh."
        }

        return "\(result.summary.failedCount) sources failed to refresh."
    }
}

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

private struct ArticleListRowView: View {
    let article: ArticleListItemDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(article.feedTitle)
                    .font(.caption)
                    .foregroundStyle(metadataForegroundStyle)
                    .lineLimit(1)

                Spacer(minLength: 0)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if article.isStarred {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }

                    Text(ArticleListRowTimeFormatter.string(for: article))
                        .font(.caption)
                        .foregroundStyle(metadataForegroundStyle)
                        .lineLimit(1)
                }
            }

            Text(ArticleListRowContent.primaryText(for: article))
                .font(.body)
                .foregroundStyle(titleForegroundStyle)
                .multilineTextAlignment(.leading)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
    }

    private var titleForegroundStyle: AnyShapeStyle {
        article.isRead
            ? AnyShapeStyle(.tertiary)
            : AnyShapeStyle(.primary)
    }

    private var metadataForegroundStyle: AnyShapeStyle {
        article.isRead
            ? AnyShapeStyle(.tertiary)
            : AnyShapeStyle(.secondary)
    }
}

private enum ArticleListRowContent {
    static func primaryText(for article: ArticleListItemDTO) -> String {
        guard let summary = article.summary?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            summary.isEmpty == false,
            summary != article.title
        else {
            return article.title
        }

        return summary
    }
}

private enum ArticleListRowTimeFormatter {
    static func string(for article: ArticleListItemDTO) -> String {
        let referenceDate = article.publishedAt ?? article.fetchedAt
        return referenceDate.formatted(
            .dateTime
                .hour(.twoDigits(amPM: .omitted))
                .minute(.twoDigits)
        )
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

private struct ArticleListSectionHeaderView: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(nil)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("Loading") {
    ArticleListPreviewContainer(
        screenState: .previewLoading(
            selection: .unread,
            navigationTitle: "Unread",
            navigationSubtitle: "46 Unread Items"
        )
    )
}

#Preview("Articles Multi-Day") {
    ArticleListPreviewContainer(
        screenState: .previewLoaded(
            selection: .unread,
            navigationTitle: "Unread",
            navigationSubtitle: "7 Unread Items",
            articles: ArticleListPreviewData.multiDayArticles
        )
    )
}

#Preview("Loading Error") {
    ArticleListPreviewContainer(
        screenState: .previewFailed(
            selection: .unread,
            navigationTitle: "Unread",
            navigationSubtitle: "0 Unread Items",
            message: "The selected source could not be loaded from persistence."
        )
    )
}

private struct ArticleListPreviewContainer: View {
    let screenState: ArticlesScreenState
    @State private var selection: UUID? = nil

    var body: some View {
        NavigationStack {
            ArticleListView(
                selectedSidebarSelection: .unread,
                selectedSourcesFilter: .unread,
                reloadID: UUID(),
                showsBackButton: true,
                navigateBackToSources: {},
                previewScreenState: screenState,
                selection: $selection
            )
        }
        .environment(AppState())
    }
}

private enum ArticleListPreviewData {
    static var multiDayArticles: [ArticleListItemDTO] {
        let calendar = Calendar.current
        let now = Date()

        let todayMorning = calendar.date(bySettingHour: 7, minute: 12, second: 0, of: now) ?? now
        let todayEarlier = calendar.date(bySettingHour: 6, minute: 25, second: 0, of: now) ?? now
        let yesterdayBase = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        let yesterdayLate = calendar.date(bySettingHour: 23, minute: 54, second: 0, of: yesterdayBase) ?? yesterdayBase
        let yesterdayEvening = calendar.date(bySettingHour: 21, minute: 31, second: 0, of: yesterdayBase) ?? yesterdayBase
        let olderBase = calendar.date(byAdding: .day, value: -2, to: now) ?? now
        let olderEvening = calendar.date(bySettingHour: 17, minute: 32, second: 0, of: olderBase) ?? olderBase
        let olderAfternoon = calendar.date(bySettingHour: 15, minute: 21, second: 0, of: olderBase) ?? olderBase

        return [
            makeArticle(
                feedTitle: "T-Ж",
                title: "Занимайтесь с отягощением минимум дважды в неделю: совет тренера",
                summary: "Краткий пересказ ключевой новости за сегодня, чтобы на экране было видно вторую строку.",
                publishedAt: todayMorning
            ),
            makeArticle(
                feedTitle: "T-Ж",
                title: "Чешме: что нужно знать перед поездкой",
                summary: "Ещё один короткий анонс статьи, который останется в пределах двух строк.",
                publishedAt: todayEarlier
            ),
            makeArticle(
                feedTitle: "N+1",
                title: "Экипаж Ориона сфотографировал ночную Землю на пути к Луне",
                summary: "Материал за вчера, чтобы следующая секция была заметна в превью.",
                publishedAt: yesterdayLate
            ),
            makeArticle(
                feedTitle: "N+1",
                title: "Древнейшие лошади из Китая оказались ослами",
                summary: "Вторая статья в секции вчерашних публикаций.",
                publishedAt: yesterdayEvening
            ),
            makeArticle(
                feedTitle: "Журнал «Код»",
                title: "У Сбера, Т-Банка и ВТБ массовый сбой",
                summary: "Статья для более старой даты, где позже появится форматированный header с датой.",
                publishedAt: olderEvening
            ),
            makeArticle(
                feedTitle: "N+1",
                title: "FDA одобрило первый низкомолекулярный оральный агонист ГПП-1 для снижения массы тела",
                summary: "Ещё один пример из более старой секции списка.",
                publishedAt: olderAfternoon
            )
        ]
    }

    private static func makeArticle(
        feedTitle: String,
        title: String,
        summary: String,
        publishedAt: Date
    ) -> ArticleListItemDTO {
        ArticleListItemDTO(
            id: UUID(),
            feedID: UUID(),
            feedTitle: feedTitle,
            articleExternalID: UUID().uuidString,
            title: title,
            summary: summary,
            author: nil,
            publishedAt: publishedAt,
            fetchedAt: publishedAt,
            isRead: false,
            isStarred: false,
            isHidden: false
        )
    }
}
