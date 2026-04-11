import SwiftUI

struct ArticleListView: View {
    @Environment(\.appDependencies) private var dependencies
    let selectedSidebarSelection: SidebarSelection?
    let selectedFilter: ArticleListFilter
    let selectedSourcesFilter: SourcesFilter
    let reloadID: UUID
    @Binding var selection: UUID?
    @State private var articles: [ArticleListItemDTO] = []
    @State private var hasLoadedArticles = false
    @State private var lastLoadedSourceSelection: SidebarSelection? = nil

    var body: some View {
        List(articles, id: \.id, selection: $selection) { article in
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
        .overlay {
            if hasLoadedArticles {
                if selectedSidebarSelection == nil {
                    ContentUnavailableView(
                        "No Source Selected",
                        systemImage: "sidebar.left",
                        description: Text("Select Inbox or a feed in the sidebar to load articles.")
                    )
                } else if articles.isEmpty {
                    ContentUnavailableView(
                        "No Articles",
                        systemImage: "newspaper",
                        description: Text(emptyStateDescription)
                    )
                }
            }
        }
        .task(id: ArticleListLoadContext(
            sourceSelection: selectedSidebarSelection,
            filter: selectedFilter,
            reloadID: reloadID
        )) {
            await loadArticles()
        }
    }

    @MainActor
    private func loadArticles() async {
        let sourceSelectionChanged = lastLoadedSourceSelection != selectedSidebarSelection
        if sourceSelectionChanged {
            articles = []
            selection = nil
            hasLoadedArticles = false
        }
        defer {
            hasLoadedArticles = true
            lastLoadedSourceSelection = selectedSidebarSelection
        }

        guard let articleQueryService = dependencies.articleQueryService else {
            articles = []
            selection = nil
            return
        }

        let sortMode = await loadSortMode()

        do {
            switch selectedSidebarSelection {
            case .inbox:
                articles = try articleQueryService.fetchInboxListItems(
                    sortMode: sortMode,
                    filter: selectedFilter
                )
            case .unread:
                articles = try articleQueryService.fetchInboxListItems(
                    sortMode: sortMode,
                    filter: .unread
                )
            case .starred:
                articles = try articleQueryService.fetchInboxListItems(
                    sortMode: sortMode,
                    filter: .starred
                )
            case .folder(let folderName):
                articles = try articleQueryService.fetchFolderListItems(
                    folderName: folderName,
                    sortMode: sortMode,
                    filter: FolderArticleListFilterResolver.resolve(for: selectedSourcesFilter)
                )
            case .feed(let selectedFeedID):
                articles = try articleQueryService.fetchArticleListItems(
                    feedID: selectedFeedID,
                    sortMode: sortMode,
                    filter: selectedFilter
                )
            case .none:
                articles = []
            }
        } catch {
            dependencies.logger.error("Failed to load article list for selection \(String(describing: selectedSidebarSelection)): \(error)")
            articles = []
        }

        self.selection = stabilizedSelection(availableArticleIDs: articles.map(\.id))
    }

    private var emptyStateDescription: String {
        switch selectedSidebarSelection {
        case .inbox:
            "Your global inbox has no stored articles yet."
        case .unread:
            "There are no unread articles in your sources."
        case .starred:
            "You have not starred any articles yet."
        case .folder(let folderName):
            "\(folderName) has no articles for the active sources filter."
        case .feed:
            "This feed has no stored articles yet."
        case .none:
            "Select Inbox or a feed in the sidebar to load articles."
        }
    }

    private func stabilizedSelection(availableArticleIDs: [UUID]) -> UUID? {
        if let selection, availableArticleIDs.contains(selection) {
            return selection
        }
        return availableArticleIDs.first
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
    let reloadID: UUID
}

enum FolderArticleListFilterResolver {
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
                selection: $selection
            )
        }
    }
    return PreviewContainer()
        .environment(AppState())
        .environment(\.appDependencies, AppDependencies.makeDefault())
}
