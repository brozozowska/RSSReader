import SwiftUI

struct ArticleListView: View {
    @Environment(\.appDependencies) private var dependencies
    let selectedSidebarSelection: SidebarSelection?
    let selectedFilter: ArticleListFilter
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
        .navigationTitle("Articles")
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
            filter: selectedFilter,
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
        screenState.beginLoading(
            for: selectedSidebarSelection,
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
                    filter: selectedFilter
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
                selection: selectedSidebarSelection
            )
        } catch {
            dependencies.logger.error("Failed to load article list for selection \(String(describing: selectedSidebarSelection)): \(error)")
            screenState.applyLoadingFailure(
                error.localizedDescription,
                selection: selectedSidebarSelection,
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
    let filter: ArticleListFilter
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
                selectedFilter: .all,
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
