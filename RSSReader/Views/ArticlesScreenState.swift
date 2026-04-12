import Foundation

enum ArticlesScreenPhase: Equatable {
    case noSelection
    case loading
    case loaded
    case empty
    case failed(String)
}

enum ArticlesScreenRefreshState: Equatable {
    case idle
    case refreshing
}

enum ArticlesScreenConfirmationDialog: Equatable {
    case markAllAsRead
}

struct ArticlesScreenPlaceholderState: Equatable {
    let title: String
    let systemImage: String
    let description: String?
}

struct ArticlesScreenNavigationTitleResolver {
    static func resolve(
        selection: SidebarSelection?,
        selectedFeedTitle: String? = nil
    ) -> String {
        switch selection {
        case .none:
            "Articles"
        case .inbox:
            "All Items"
        case .unread:
            "Unread"
        case .starred:
            "Starred"
        case .folder(let folderName):
            folderName
        case .feed:
            selectedFeedTitle ?? "Source"
        }
    }
}

struct ArticlesScreenSubtitleResolver {
    static func resolve(
        articles: [ArticleListItemDTO],
        sourcesFilter: SourcesFilter
    ) -> String {
        let count: Int
        let itemLabel: String

        switch sourcesFilter {
        case .allItems, .unread:
            count = articles.filter { $0.isRead == false }.count
            itemLabel = count == 1 ? "Unread Item" : "Unread Items"
        case .starred:
            count = articles.filter(\.isStarred).count
            itemLabel = count == 1 ? "Starred Item" : "Starred Items"
        }

        return "\(count) \(itemLabel)"
    }
}

struct ArticlesScreenToolbarActionsState: Equatable {
    let showsSearchAction: Bool
    let showsMenuAction: Bool
    let isMarkAllAsReadEnabled: Bool

    init(selection: SidebarSelection?, visibleArticles: [ArticleListItemDTO]) {
        let hasSelection = selection != nil
        self.showsSearchAction = hasSelection
        self.showsMenuAction = hasSelection
        self.isMarkAllAsReadEnabled = visibleArticles.contains(where: { $0.isRead == false })
    }
}

struct ArticlesDaySection: Identifiable, Equatable {
    let date: Date
    let title: String
    var articles: [ArticleListItemDTO]

    var id: Date { date }
}

enum ArticlesDaySectionsBuilder {
    static func build(
        from articles: [ArticleListItemDTO],
        calendar: Calendar = .current
    ) -> [ArticlesDaySection] {
        var sections: [ArticlesDaySection] = []

        for article in articles {
            let referenceDate = article.publishedAt ?? article.fetchedAt
            let day = calendar.startOfDay(for: referenceDate)

            if sections.last?.date == day {
                sections[sections.count - 1].articles.append(article)
                continue
            }

            sections.append(
                ArticlesDaySection(
                    date: day,
                    title: title(for: day, calendar: calendar),
                    articles: [article]
                )
            )
        }

        return sections
    }

    static func title(
        for day: Date,
        calendar: Calendar = .current
    ) -> String {
        if calendar.isDateInToday(day) {
            return "Today"
        }

        if calendar.isDateInYesterday(day) {
            return "Yesterday"
        }

        return day.formatted(
            .dateTime
                .weekday(.wide)
                .day()
                .month(.wide)
                .year()
        )
    }
}

struct ArticleRowSwipeActionsState: Equatable {
    let canMarkAsRead: Bool
    let starActionTitle: String
    let starActionSystemImage: String

    init(article: ArticleListItemDTO) {
        self.canMarkAsRead = article.isRead == false
        self.starActionTitle = article.isStarred ? "Unstar" : "Star"
        self.starActionSystemImage = article.isStarred ? "star.slash" : "star"
    }
}

struct ArticlesScreenState {
    private(set) var articles: [ArticleListItemDTO] = []
    private(set) var selection: SidebarSelection?
    private(set) var navigationTitle = "Articles"
    private(set) var navigationSubtitle = "0 Unread Items"
    private(set) var phase: ArticlesScreenPhase = .noSelection
    private(set) var refreshState: ArticlesScreenRefreshState = .idle
    private(set) var toolbarActions = ArticlesScreenToolbarActionsState(
        selection: nil,
        visibleArticles: []
    )
    var pendingConfirmation: ArticlesScreenConfirmationDialog?

    var placeholder: ArticlesScreenPlaceholderState? {
        switch phase {
        case .noSelection:
            ArticlesScreenPlaceholderState(
                title: "No Source Selected",
                systemImage: "sidebar.left",
                description: "Select Inbox or a feed in the sidebar to load articles."
            )
        case .loading, .loaded:
            nil
        case .empty:
            ArticlesScreenPlaceholderState(
                title: "No Articles",
                systemImage: "newspaper",
                description: emptyStateDescription
            )
        case .failed(let message):
            ArticlesScreenPlaceholderState(
                title: "Failed to Load Articles",
                systemImage: "exclamationmark.triangle",
                description: message
            )
        }
    }

    var showsPrimaryLoadingIndicator: Bool {
        phase == .loading && articles.isEmpty
    }

    var sections: [ArticlesDaySection] {
        ArticlesDaySectionsBuilder.build(from: articles)
    }

    mutating func beginLoading(
        for selection: SidebarSelection?,
        navigationTitle: String,
        navigationSubtitle: String,
        resetsContent: Bool
    ) {
        pendingConfirmation = nil
        self.selection = selection
        self.navigationTitle = navigationTitle
        self.navigationSubtitle = navigationSubtitle

        guard selection != nil else {
            articles = []
            phase = .noSelection
            refreshState = .idle
            updateToolbarActions(for: selection)
            return
        }

        if resetsContent || articles.isEmpty {
            if resetsContent {
                articles = []
            }
            phase = .loading
            refreshState = .idle
        } else {
            refreshState = .refreshing
        }

        updateToolbarActions(for: selection)
    }

    mutating func applyLoadedArticles(
        _ loadedArticles: [ArticleListItemDTO],
        selection: SidebarSelection?,
        navigationTitle: String,
        navigationSubtitle: String
    ) {
        self.selection = selection
        self.navigationTitle = navigationTitle
        self.navigationSubtitle = navigationSubtitle
        articles = loadedArticles
        refreshState = .idle

        if selection == nil {
            phase = .noSelection
        } else if loadedArticles.isEmpty {
            phase = .empty
        } else {
            phase = .loaded
        }

        updateToolbarActions(for: selection)
    }

    mutating func applyLoadingFailure(
        _ message: String,
        selection: SidebarSelection?,
        navigationTitle: String,
        navigationSubtitle: String,
        retainsContent: Bool
    ) {
        self.selection = selection
        self.navigationTitle = navigationTitle
        self.navigationSubtitle = navigationSubtitle
        refreshState = .idle

        if retainsContent && articles.isEmpty == false {
            phase = .loaded
        } else if selection == nil {
            articles = []
            phase = .noSelection
        } else {
            articles = []
            phase = .failed(message)
        }

        updateToolbarActions(for: selection)
    }

    mutating func presentMarkAllAsReadConfirmation() {
        guard toolbarActions.isMarkAllAsReadEnabled else { return }
        pendingConfirmation = .markAllAsRead
    }

    mutating func dismissConfirmation() {
        pendingConfirmation = nil
    }

    private mutating func updateToolbarActions(for selection: SidebarSelection?) {
        toolbarActions = ArticlesScreenToolbarActionsState(
            selection: selection,
            visibleArticles: articles
        )
    }

    private var emptyStateDescription: String {
        switch selection {
        case .none:
            "Select Inbox or a feed in the sidebar to load articles."
        case .inbox:
            "Your global inbox has no stored articles yet."
        case .unread:
            "There are no unread articles in your sources."
        case .starred:
            "You have not starred any articles yet."
        case .folder(let folderName):
            "\(folderName) has no articles for the active sources filter."
        case .feed:
            "This source has no articles for the active sources filter."
        }
    }
}

extension ArticlesScreenState {
    static func previewLoading(
        selection: SidebarSelection,
        navigationTitle: String,
        navigationSubtitle: String
    ) -> ArticlesScreenState {
        var state = ArticlesScreenState()
        state.beginLoading(
            for: selection,
            navigationTitle: navigationTitle,
            navigationSubtitle: navigationSubtitle,
            resetsContent: true
        )
        return state
    }

    static func previewLoaded(
        selection: SidebarSelection,
        navigationTitle: String,
        navigationSubtitle: String,
        articles: [ArticleListItemDTO]
    ) -> ArticlesScreenState {
        var state = ArticlesScreenState()
        state.applyLoadedArticles(
            articles,
            selection: selection,
            navigationTitle: navigationTitle,
            navigationSubtitle: navigationSubtitle
        )
        return state
    }

    static func previewFailed(
        selection: SidebarSelection,
        navigationTitle: String,
        navigationSubtitle: String,
        message: String
    ) -> ArticlesScreenState {
        var state = ArticlesScreenState()
        state.applyLoadingFailure(
            message,
            selection: selection,
            navigationTitle: navigationTitle,
            navigationSubtitle: navigationSubtitle,
            retainsContent: false
        )
        return state
    }
}
