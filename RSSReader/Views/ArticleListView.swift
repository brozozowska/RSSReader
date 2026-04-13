import SwiftUI

struct ArticleListView: View {
    @Environment(\.appDependencies) private var dependencies
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
            if screenState.showsPrimaryLoadingIndicator {
                ProgressView()
            } else if let placeholder = searchPlaceholder(for: visibleArticles) {
                ContentUnavailableView(
                    placeholder.title,
                    systemImage: placeholder.systemImage,
                    description: placeholder.description.map(Text.init)
                )
            } else if let placeholder = screenState.placeholder {
                ContentUnavailableView(
                    placeholder.title,
                    systemImage: placeholder.systemImage,
                    description: placeholder.description.map(Text.init)
                )
            }
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
