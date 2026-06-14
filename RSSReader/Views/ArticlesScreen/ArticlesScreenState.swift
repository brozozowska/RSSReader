import Foundation

struct ArticlesScreenState {
    private(set) var articleListSession = ArticleListSession(context: .noSelection)
    private(set) var selection: SidebarSelection?
    private(set) var navigationTitle = ReadingLocalization.articlesTitle
    private(set) var navigationSubtitle = ReadingLocalization.noUnreadItemsSubtitle
    private(set) var phase: ArticlesScreenPhase = .noSelection
    private(set) var refreshState: ArticlesScreenRefreshState = .idle
    private(set) var customRefreshState: ArticlesScreenCustomRefreshState = .idle
    private(set) var refreshFeedback: ArticlesScreenRefreshFeedback?
    private(set) var toolbarActions = ArticlesScreenToolbarActionsState(
        selection: nil,
        visibleArticles: [],
        phase: .noSelection
    )
    var pendingConfirmation: ArticlesScreenConfirmationDialog?

    var articles: [ArticleListItemDTO] {
        articleListSession.articles
    }

    var placeholder: ArticlesScreenPlaceholderState? {
        switch phase {
        case .noSelection:
            ArticlesScreenPlaceholderState(
                title: ReadingLocalization.noSourceSelectedTitle,
                systemImage: "sidebar.left",
                description: ReadingLocalization.noSourceSelectedDescription
            )
        case .loading, .loaded:
            nil
        case .empty:
            ArticlesScreenPlaceholderState(
                title: ReadingLocalization.noArticlesTitle,
                systemImage: "newspaper",
                description: emptyStateDescription
            )
        case .failed(let message):
            ArticlesScreenPlaceholderState(
                title: ReadingLocalization.failedToLoadArticlesTitle,
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
        resetsContent: Bool,
        sessionContext: ArticleListSession.Context? = nil
    ) {
        pendingConfirmation = nil
        self.selection = selection
        self.navigationTitle = navigationTitle
        self.navigationSubtitle = navigationSubtitle
        let resolvedSessionContext = resolvedContext(
            selection: selection,
            sessionContext: sessionContext
        )

        guard selection != nil else {
            articleListSession.replaceArticles([], context: resolvedSessionContext)
            phase = .noSelection
            refreshState = .idle
            customRefreshState = .idle
            refreshFeedback = nil
            updateToolbarActions(for: selection)
            return
        }

        if resetsContent || articles.isEmpty {
            refreshFeedback = nil
            customRefreshState = .idle
            if resetsContent {
                articleListSession.replaceArticles([], context: resolvedSessionContext)
            }
            phase = .loading
            refreshState = .idle
        } else {
            articleListSession.replaceEntries(
                articleListSession.entries,
                context: resolvedSessionContext
            )
            refreshState = .refreshing
        }

        updateToolbarActions(for: selection)
    }

    mutating func applyLoadedArticles(
        _ loadedArticles: [ArticleListItemDTO],
        selection: SidebarSelection?,
        navigationTitle: String,
        navigationSubtitle: String,
        sessionContext: ArticleListSession.Context? = nil,
        preservesRefreshFeedback: Bool = false
    ) {
        applyLoadedEntries(
            loadedArticles.map { ArticleListEntry(article: $0) },
            selection: selection,
            navigationTitle: navigationTitle,
            navigationSubtitle: navigationSubtitle,
            sessionContext: sessionContext,
            preservesRefreshFeedback: preservesRefreshFeedback
        )
    }

    mutating func applyLoadedEntries(
        _ loadedEntries: [ArticleListEntry],
        selection: SidebarSelection?,
        navigationTitle: String,
        navigationSubtitle: String,
        sessionContext: ArticleListSession.Context? = nil,
        preservesRefreshFeedback: Bool = false
    ) {
        self.selection = selection
        self.navigationTitle = navigationTitle
        self.navigationSubtitle = navigationSubtitle
        articleListSession.replaceEntries(
            loadedEntries,
            context: resolvedContext(
                selection: selection,
                sessionContext: sessionContext
            )
        )
        refreshState = .idle
        customRefreshState = .idle
        if preservesRefreshFeedback == false {
            refreshFeedback = nil
        }

        if selection == nil {
            phase = .noSelection
        } else if loadedEntries.isEmpty {
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
        retainsContent: Bool,
        sessionContext: ArticleListSession.Context? = nil
    ) {
        self.selection = selection
        self.navigationTitle = navigationTitle
        self.navigationSubtitle = navigationSubtitle
        let resolvedSessionContext = resolvedContext(
            selection: selection,
            sessionContext: sessionContext
        )
        refreshState = .idle
        customRefreshState = .idle

        if retainsContent && articles.isEmpty == false {
            phase = .loaded
            refreshFeedback = ArticlesScreenRefreshFeedback(message: message)
        } else if selection == nil {
            articleListSession.replaceArticles([], context: resolvedSessionContext)
            phase = .noSelection
            refreshFeedback = nil
        } else {
            articleListSession.replaceArticles([], context: resolvedSessionContext)
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
        articleListSession.replaceArticles(
            updatedArticles,
            context: articleListSession.context
        )
        self.navigationSubtitle = navigationSubtitle
        pendingConfirmation = nil
        refreshState = .idle
        customRefreshState = .idle

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
        case .update(let updatedArticle, let membershipStatus):
            articleListSession.updateArticle(
                updatedArticle,
                membershipStatus: membershipStatus
            )
        case .remove:
            articleListSession.removeArticle(id: articleID)
        }

        self.navigationSubtitle = navigationSubtitle
        refreshState = .idle
        customRefreshState = .idle

        if selection == nil {
            phase = .noSelection
        } else if articles.isEmpty {
            phase = .empty
        } else {
            phase = .loaded
        }

        updateToolbarActions(for: selection)
    }

    mutating func updateCustomRefreshPullProgress(_ progress: Double) {
        guard customRefreshState.phase != .refreshing else { return }
        customRefreshState = .pulling(progress: progress)
    }

    mutating func beginCustomRefresh() {
        customRefreshState = .refreshing
    }

    mutating func endCustomRefresh() {
        customRefreshState = .idle
    }

    mutating func markArticleAsReadInCurrentSession(articleID: UUID) {
        articleListSession.markArticleAsReadInCurrentSession(id: articleID)
        navigationSubtitle = ArticlesScreenSubtitleResolver.resolve(
            articles: articles,
            sourcesFilter: articleListSession.context.sourcesFilter
        )

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

    private func resolvedContext(
        selection: SidebarSelection?,
        sessionContext: ArticleListSession.Context?
    ) -> ArticleListSession.Context {
        sessionContext ?? ArticleListSession.Context(
            selection: selection,
            sourcesFilter: articleListSession.context.sourcesFilter
        )
    }

    private var emptyStateDescription: String {
        switch selection {
        case .none:
            ReadingLocalization.noSourceSelectedDescription
        case .inbox:
            ReadingLocalization.inboxEmptyDescription
        case .unread:
            ReadingLocalization.unreadEmptyDescription
        case .starred:
            ReadingLocalization.starredEmptyDescription
        case .folder(let folderName):
            ReadingLocalization.folderEmptyDescription(folderName: folderName)
        case .feed:
            ReadingLocalization.sourceEmptyDescription
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
