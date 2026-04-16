import Foundation

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
        visibleArticles: [],
        phase: .noSelection
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
        refreshFeedback = nil

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
            visibleArticles: articles,
            phase: phase
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
