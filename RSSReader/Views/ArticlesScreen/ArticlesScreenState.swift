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
    private(set) var emptyContentKind: ArticlesScreenEmptyContentKind = .selection
    private(set) var listAnimationState = ArticleListAnimationState()
    private(set) var isLoadingNextPage = false
    private(set) var toolbarActions = ArticlesScreenToolbarActionsState(
        selection: nil,
        visibleArticles: [],
        phase: .noSelection
    )
    var pendingConfirmation: ArticlesScreenConfirmationDialog?

    var articles: [ArticleListItemDTO] {
        articleListSession.articles
    }

    var canLoadNextPage: Bool {
        articleListSession.nextPageCursor != nil && isLoadingNextPage == false
    }

    var placeholder: ArticlesScreenPlaceholderState? {
        switch phase {
        case .noSelection:
            ArticlesScreenPlaceholderState(
                title: ReadingLocalization.noSidebarSelectionTitle,
                systemImage: "sidebar.left",
                description: ReadingLocalization.noSidebarSelectionDescription
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

    mutating func endPresentation() {
        beginLoading(
            for: nil,
            navigationTitle: ReadingLocalization.articlesTitle,
            navigationSubtitle: ReadingLocalization.noUnreadItemsSubtitle,
            resetsContent: true,
            startsNewSession: true,
            sessionContext: .noSelection
        )
    }

    mutating func beginLoading(
        for selection: SidebarSelection?,
        navigationTitle: String,
        navigationSubtitle: String,
        resetsContent: Bool,
        startsNewSession: Bool = false,
        sessionContext: ArticleListSession.Context? = nil
    ) {
        pendingConfirmation = nil
        isLoadingNextPage = false
        emptyContentKind = .selection
        self.selection = selection
        self.navigationTitle = navigationTitle
        self.navigationSubtitle = navigationSubtitle
        let resolvedSessionContext = resolvedContext(
            selection: selection,
            sessionContext: sessionContext
        )

        if startsNewSession {
            articleListSession.startNewSession(
                context: resolvedSessionContext,
                retainsCurrentEntries: resetsContent == false
            )
        }

        guard selection != nil else {
            listAnimationState.prepareForSnapshotReplacement()
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
                listAnimationState.prepareForSnapshotReplacement()
                articleListSession.replaceArticles([], context: resolvedSessionContext)
            }
            phase = .loading
            refreshState = .idle
        } else {
            articleListSession.replaceEntries(
                articleListSession.entries,
                context: resolvedSessionContext,
                nextPageCursor: articleListSession.nextPageCursor
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
        preservesRefreshFeedback: Bool = false,
        emptyContentKind: ArticlesScreenEmptyContentKind = .selection,
        nextPageCursor: ArticleSearchRequest.Cursor? = nil
    ) {
        applyLoadedEntries(
            loadedArticles.map { ArticleListEntry(article: $0) },
            selection: selection,
            navigationTitle: navigationTitle,
            navigationSubtitle: navigationSubtitle,
            sessionContext: sessionContext,
            preservesRefreshFeedback: preservesRefreshFeedback,
            emptyContentKind: emptyContentKind,
            nextPageCursor: nextPageCursor
        )
    }

    mutating func applyLoadedEntries(
        _ loadedEntries: [ArticleListEntry],
        selection: SidebarSelection?,
        navigationTitle: String,
        navigationSubtitle: String,
        sessionContext: ArticleListSession.Context? = nil,
        preservesRefreshFeedback: Bool = false,
        emptyContentKind: ArticlesScreenEmptyContentKind = .selection,
        nextPageCursor: ArticleSearchRequest.Cursor? = nil
    ) {
        listAnimationState.prepareForSnapshotReplacement()
        self.selection = selection
        self.navigationTitle = navigationTitle
        self.navigationSubtitle = navigationSubtitle
        self.emptyContentKind = loadedEntries.isEmpty ? emptyContentKind : .selection
        articleListSession.replaceEntries(
            loadedEntries,
            context: resolvedContext(
                selection: selection,
                sessionContext: sessionContext
            ),
            nextPageCursor: nextPageCursor
        )
        isLoadingNextPage = false
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

    @discardableResult
    mutating func beginLoadingNextPage() -> Bool {
        guard canLoadNextPage else { return false }
        isLoadingNextPage = true
        return true
    }

    mutating func applyLoadedNextPage(
        _ articles: [ArticleListItemDTO],
        nextPageCursor: ArticleSearchRequest.Cursor?,
        navigationSubtitle: String
    ) {
        if articles.isEmpty == false {
            listAnimationState.prepareForLocalMutation()
        }
        articleListSession.appendPage(
            articles,
            nextPageCursor: nextPageCursor
        )
        self.navigationSubtitle = navigationSubtitle
        isLoadingNextPage = false
        if self.articles.isEmpty == false {
            phase = .loaded
            emptyContentKind = .selection
        }
        updateToolbarActions(for: selection)
    }

    mutating func endLoadingNextPage() {
        isLoadingNextPage = false
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
        emptyContentKind = .selection
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
            listAnimationState.prepareForSnapshotReplacement()
            articleListSession.replaceArticles([], context: resolvedSessionContext)
            phase = .noSelection
            refreshFeedback = nil
        } else {
            listAnimationState.prepareForSnapshotReplacement()
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
        navigationSubtitle: String,
        emptyContentKind: ArticlesScreenEmptyContentKind? = nil
    ) {
        listAnimationState.prepareForLocalMutation()
        articleListSession.replaceArticles(
            updatedArticles,
            context: articleListSession.context,
            nextPageCursor: articleListSession.nextPageCursor
        )
        self.navigationSubtitle = navigationSubtitle
        if updatedArticles.isEmpty {
            self.emptyContentKind = emptyContentKind ?? inferredEmptyContentKind()
        } else {
            self.emptyContentKind = .selection
        }
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
        listAnimationState.prepareForLocalMutation()
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
        if articles.isEmpty {
            emptyContentKind = inferredEmptyContentKind()
        } else {
            emptyContentKind = .selection
        }

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
        listAnimationState.prepareForLocalMutation()
        articleListSession.markArticleAsReadInCurrentSession(id: articleID)
        navigationSubtitle = ArticlesScreenSubtitleResolver.resolve(
            articles: articles,
            sidebarArticleFilter: articleListSession.context.sidebarArticleFilter,
            hasMorePages: articleListSession.nextPageCursor != nil
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
            sidebarArticleFilter: articleListSession.context.sidebarArticleFilter
        )
    }

    private func inferredEmptyContentKind() -> ArticlesScreenEmptyContentKind {
        articleListSession.context.normalizedSearchText.isEmpty ? .selection : .searchResults
    }

    private var emptyStateDescription: String {
        switch selection {
        case .none:
            ReadingLocalization.noSidebarSelectionDescription
        case .inbox:
            ReadingLocalization.inboxEmptyDescription
        case .unread:
            ReadingLocalization.unreadEmptyDescription
        case .starred:
            ReadingLocalization.starredEmptyDescription
        case .folder(let folderName):
            ReadingLocalization.folderEmptyDescription(folderName: folderName)
        case .feed:
            ReadingLocalization.feedEmptyDescription
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
