import SwiftUI

struct ArticleListView: View {
    @Environment(\.appDependencies) private var dependencies
    let selectedSidebarSelection: SidebarSelection?
    let selectedSourcesFilter: SourcesFilter
    let reloadID: UUID
    let showsBackButton: Bool
    let navigateBackToSources: () -> Void
    @Binding var selection: UUID?
    @State private var screenState = ArticlesScreenState()
    @State private var lastLoadedSourceSelection: SidebarSelection? = nil

    var body: some View {
        List(screenState.articles, id: \.id, selection: $selection) { article in
            VStack(alignment: .leading, spacing: 4) {
                Text(article.title)
                    .font(.body.weight(article.isRead ? .regular : .semibold))

                if let summary = article.summary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .navigationTitle(screenState.navigationTitle)
        .navigationSubtitle(screenState.navigationSubtitle)
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
            if screenState.showsPrimaryLoadingIndicator {
                ProgressView()
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

#Preview {
    struct PreviewContainer: View {
        @State var selection: UUID? = nil
        var body: some View {
            ArticleListView(
                selectedSidebarSelection: .inbox,
                selectedSourcesFilter: .allItems,
                reloadID: UUID(),
                showsBackButton: true,
                navigateBackToSources: {},
                selection: $selection
            )
        }
    }
    return PreviewContainer()
        .environment(AppState())
        .environment(\.appDependencies, AppDependencies.makeDefault())
}
