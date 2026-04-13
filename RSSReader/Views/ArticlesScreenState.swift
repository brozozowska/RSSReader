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

struct ArticlesScreenRefreshFeedback: Equatable {
    let message: String
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
    let showsMarkAllAsReadAction: Bool
    let isMarkAllAsReadEnabled: Bool

    init(selection: SidebarSelection?, visibleArticles: [ArticleListItemDTO]) {
        let hasSelection = selection != nil
        self.showsSearchAction = hasSelection
        self.showsMarkAllAsReadAction = hasSelection
        self.isMarkAllAsReadEnabled = visibleArticles.contains(where: { $0.isRead == false })
    }
}

struct ArticlesScreenPrimaryLoadingState: Equatable {
    let title: String
    let description: String
}

struct ArticlesScreenRefreshBannerState: Equatable {
    enum Style: Equatable {
        case refreshing
        case failed
    }

    let style: Style
    let title: String
    let message: String

    var showsActivityIndicator: Bool {
        style == .refreshing
    }

    var showsRetryAction: Bool {
        style == .failed
    }

    var showsDismissAction: Bool {
        style == .failed
    }
}

struct ArticlesScreenDerivedViewState {
    let visibleArticles: [ArticleListItemDTO]
    let sections: [ArticlesDaySection]
    let toolbarActions: ArticlesScreenToolbarActionsState
    let searchPlaceholder: ArticlesScreenPlaceholderState?
    let refreshBanner: ArticlesScreenRefreshBannerState?
    let primaryLoadingState: ArticlesScreenPrimaryLoadingState?
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

enum ArticleRowMutation: Equatable {
    case update(ArticleListItemDTO)
    case remove
}

struct ArticlesScreenState {
    private(set) var articles: [ArticleListItemDTO] = []
    private(set) var selection: SidebarSelection?
    private(set) var navigationTitle = "Articles"
    private(set) var navigationSubtitle = "0 Unread Items"
    private(set) var phase: ArticlesScreenPhase = .noSelection
    private(set) var refreshState: ArticlesScreenRefreshState = .idle
    private(set) var refreshFeedback: ArticlesScreenRefreshFeedback?
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

    var primaryFailureMessage: String? {
        guard case .failed(let message) = phase else {
            return nil
        }
        return message
    }

    var showsRefreshActivityIndicator: Bool {
        refreshState == .refreshing && articles.isEmpty == false
    }

    var sections: [ArticlesDaySection] {
        ArticlesDaySectionsBuilder.build(from: articles)
    }

    func derivedViewState(searchText: String) -> ArticlesScreenDerivedViewState {
        let normalizedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let visibleArticles = filteredArticles(matching: normalizedSearchText)

        return ArticlesScreenDerivedViewState(
            visibleArticles: visibleArticles,
            sections: ArticlesDaySectionsBuilder.build(from: visibleArticles),
            toolbarActions: ArticlesScreenToolbarActionsState(
                selection: selection,
                visibleArticles: visibleArticles
            ),
            searchPlaceholder: searchPlaceholder(
                normalizedSearchText: normalizedSearchText,
                visibleArticles: visibleArticles
            ),
            refreshBanner: refreshBannerState,
            primaryLoadingState: primaryLoadingState
        )
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
            refreshFeedback = nil
            updateToolbarActions(for: selection)
            return
        }

        if resetsContent || articles.isEmpty {
            refreshFeedback = nil
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
            refreshFeedback = ArticlesScreenRefreshFeedback(message: message)
        } else if selection == nil {
            articles = []
            phase = .noSelection
            refreshFeedback = nil
        } else {
            articles = []
            phase = .failed(message)
            refreshFeedback = nil
        }

        updateToolbarActions(for: selection)
    }

    mutating func presentRefreshFailure(_ message: String) {
        guard message.isEmpty == false else { return }
        refreshFeedback = ArticlesScreenRefreshFeedback(message: message)
    }

    mutating func dismissRefreshFeedback() {
        refreshFeedback = nil
    }

    mutating func presentMarkAllAsReadConfirmation() {
        guard toolbarActions.isMarkAllAsReadEnabled else { return }
        pendingConfirmation = .markAllAsRead
    }

    mutating func dismissConfirmation() {
        pendingConfirmation = nil
    }

    mutating func applyMarkAllAsRead(
        _ updatedArticles: [ArticleListItemDTO],
        navigationSubtitle: String
    ) {
        articles = updatedArticles
        self.navigationSubtitle = navigationSubtitle
        pendingConfirmation = nil
        refreshState = .idle

        if selection == nil {
            phase = .noSelection
        } else if updatedArticles.isEmpty {
            phase = .empty
        } else {
            phase = .loaded
        }

        updateToolbarActions(for: selection)
    }

    mutating func applyArticleRowMutation(
        articleID: UUID,
        mutation: ArticleRowMutation,
        navigationSubtitle: String
    ) {
        switch mutation {
        case .update(let updatedArticle):
            articles = articles.map { article in
                article.id == articleID ? updatedArticle : article
            }
        case .remove:
            articles.removeAll { $0.id == articleID }
        }

        self.navigationSubtitle = navigationSubtitle
        refreshState = .idle

        if selection == nil {
            phase = .noSelection
        } else if articles.isEmpty {
            phase = .empty
        } else {
            phase = .loaded
        }

        updateToolbarActions(for: selection)
    }

    private mutating func updateToolbarActions(for selection: SidebarSelection?) {
        toolbarActions = ArticlesScreenToolbarActionsState(
            selection: selection,
            visibleArticles: articles
        )
    }

    private func filteredArticles(matching normalizedSearchText: String) -> [ArticleListItemDTO] {
        guard normalizedSearchText.isEmpty == false else {
            return articles
        }

        return articles.filter { article in
            [article.feedTitle, article.title, article.summary, article.author]
                .compactMap { $0 }
                .contains { $0.localizedCaseInsensitiveContains(normalizedSearchText) }
        }
    }

    private func searchPlaceholder(
        normalizedSearchText: String,
        visibleArticles: [ArticleListItemDTO]
    ) -> ArticlesScreenPlaceholderState? {
        guard normalizedSearchText.isEmpty == false else {
            return nil
        }

        guard phase == .loaded || phase == .empty else {
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

    private var refreshBannerState: ArticlesScreenRefreshBannerState? {
        if refreshState == .refreshing && articles.isEmpty == false {
            return ArticlesScreenRefreshBannerState(
                style: .refreshing,
                title: "Refreshing Articles",
                message: "Updating the current selection."
            )
        }

        guard let refreshFeedback else {
            return nil
        }

        return ArticlesScreenRefreshBannerState(
            style: .failed,
            title: "Refresh Failed",
            message: refreshFeedback.message
        )
    }

    private var primaryLoadingState: ArticlesScreenPrimaryLoadingState? {
        guard showsPrimaryLoadingIndicator else {
            return nil
        }

        return ArticlesScreenPrimaryLoadingState(
            title: "Loading Articles",
            description: primaryLoadingDescription
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

    private var primaryLoadingDescription: String {
        switch selection {
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
