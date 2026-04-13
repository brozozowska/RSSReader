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

    var body: some View {
        let displayedScreenState = previewScreenState ?? screenState

        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            List(selection: $selection) {
                ForEach(displayedScreenState.sections) { section in
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
            .scrollContentBackground(.hidden)
            .contentMargins(.top, 8, for: .scrollContent)
        }
        .navigationTitle(displayedScreenState.navigationTitle)
        .navigationSubtitle(displayedScreenState.navigationSubtitle)
        .toolbar {
            if showsBackButton {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: navigateBackToSources) {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel("Back to Sources")
                }
            }
        }
        .overlay {
            if displayedScreenState.showsPrimaryLoadingIndicator {
                ProgressView()
            } else if let placeholder = displayedScreenState.placeholder {
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
            guard previewScreenState == nil else { return }
            await loadArticles()
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

        self.selection = stabilizedSelection(availableArticleIDs: screenState.articles.map(\.id))
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
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text(ArticleListRowTimeFormatter.string(for: article))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(ArticleListRowContent.primaryText(for: article))
                .font(.body.weight(article.isRead ? .regular : .semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
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
            .padding(.top, 8)
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
