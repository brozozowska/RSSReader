import Foundation

struct ArticleListSession: Equatable {
    struct Context: Equatable, Sendable {
        let selection: SidebarSelection?
        let sidebarArticleFilter: SidebarArticleFilter
        let normalizedSearchText: String
        let sortMode: ArticleSortMode

        init(
            selection: SidebarSelection?,
            sidebarArticleFilter: SidebarArticleFilter,
            normalizedSearchText: String = "",
            sortMode: ArticleSortMode = .publishedAtDescending
        ) {
            self.selection = selection
            self.sidebarArticleFilter = sidebarArticleFilter
            self.normalizedSearchText = normalizedSearchText
            self.sortMode = sortMode
        }

        var articleListFilter: ArticleListFilter {
            ArticlesScreenMutationReducer.articleListFilter(
                selection: selection,
                sidebarArticleFilter: sidebarArticleFilter
            )
        }

        static let noSelection = Context(selection: nil, sidebarArticleFilter: .allItems)
    }

    private(set) var id: UUID
    private(set) var context: Context
    private(set) var entries: [ArticleListEntry]
    private(set) var nextPageCursor: ArticleSearchRequest.Cursor?
    private(set) var scopeMetric: ArticleScopeMetric?

    var articles: [ArticleListItemDTO] {
        entries.map(\.article)
    }

    init(
        context: Context,
        entries: [ArticleListEntry] = [],
        nextPageCursor: ArticleSearchRequest.Cursor? = nil,
        scopeMetric: ArticleScopeMetric? = nil
    ) {
        self.id = UUID()
        self.context = context
        self.entries = entries
        self.nextPageCursor = nextPageCursor
        self.scopeMetric = scopeMetric
    }

    init(context: Context, articles: [ArticleListItemDTO]) {
        self.init(
            context: context,
            entries: articles.map { ArticleListEntry(article: $0) }
        )
    }

    mutating func replaceArticles(
        _ articles: [ArticleListItemDTO],
        context: Context,
        nextPageCursor: ArticleSearchRequest.Cursor? = nil,
        scopeMetric: ArticleScopeMetric? = nil
    ) {
        replaceEntries(
            articles.map { ArticleListEntry(article: $0) },
            context: context,
            nextPageCursor: nextPageCursor,
            scopeMetric: scopeMetric
        )
    }

    mutating func replaceEntries(
        _ entries: [ArticleListEntry],
        context: Context,
        nextPageCursor: ArticleSearchRequest.Cursor? = nil,
        scopeMetric: ArticleScopeMetric? = nil,
        startsNewSession: Bool = false
    ) {
        let retainsScopeMetric = self.context.hasSameBaseMetricScope(as: context)
        if startsNewSession || self.context != context {
            id = UUID()
        }
        self.context = context
        self.entries = entries
        self.nextPageCursor = nextPageCursor
        self.scopeMetric = scopeMetric ?? (retainsScopeMetric ? self.scopeMetric : nil)
    }

    mutating func startNewSession(
        context: Context,
        retainsCurrentEntries: Bool
    ) {
        let canRetainCurrentEntries = retainsCurrentEntries && self.context == context
        let retainsScopeMetric = self.context.hasSameBaseMetricScope(as: context)
        id = UUID()
        self.context = context
        if retainsScopeMetric == false {
            scopeMetric = nil
        }
        if canRetainCurrentEntries == false {
            entries = []
            nextPageCursor = nil
        }
    }

    mutating func appendPage(
        _ articles: [ArticleListItemDTO],
        nextPageCursor: ArticleSearchRequest.Cursor?,
        scopeMetric: ArticleScopeMetric? = nil
    ) {
        var knownArticleIDs = Set(entries.map(\.id))
        for article in articles where knownArticleIDs.insert(article.id).inserted {
            entries.append(ArticleListEntry(article: article))
        }
        self.nextPageCursor = nextPageCursor
        if let scopeMetric {
            self.scopeMetric = scopeMetric
        }
    }

    mutating func updateArticle(
        _ article: ArticleListItemDTO,
        membershipStatus: ArticleListEntryMembershipStatus? = nil
    ) {
        let previousArticle = entries.first(where: { $0.id == article.id })?.article
        entries = entries.map { entry in
            entry.id == article.id
                ? entry.updating(article: article, membershipStatus: membershipStatus)
                : entry
        }
        if let previousArticle {
            scopeMetric = scopeMetric?.applyingMutation(
                from: previousArticle,
                to: article
            )
        }
    }

    mutating func markArticleAsReadInCurrentSession(
        id articleID: UUID,
        retainedMembershipStatus: ArticleListEntryMembershipStatus = .retainedAfterFilterMutation
    ) {
        guard let entry = entries.first(where: { $0.id == articleID }) else { return }
        updateArticle(
            entry.article.updating(
                isRead: true,
                isStarred: entry.article.isStarred
            ),
            membershipStatus: context.articleListFilter == .unread
                ? retainedMembershipStatus
                : entry.membershipStatus
        )
    }

    mutating func removeArticle(id articleID: UUID) {
        if let removedArticle = entries.first(where: { $0.id == articleID })?.article {
            scopeMetric = scopeMetric?.removing(removedArticle)
        }
        entries.removeAll { $0.id == articleID }
    }
}

private extension ArticleListSession.Context {
    func hasSameBaseMetricScope(as other: ArticleListSession.Context) -> Bool {
        selection == other.selection
            && sidebarArticleFilter == other.sidebarArticleFilter
    }
}

enum ArticleListSessionMergePolicy {
    static func merge(
        currentEntries: [ArticleListEntry],
        loadedArticles: [ArticleListItemDTO],
        retainedArticleIDs: Set<UUID>,
        retainsCurrentContent: Bool,
        retainedMembershipStatus: ArticleListEntryMembershipStatus
    ) -> [ArticleListEntry] {
        guard retainsCurrentContent else {
            return loadedArticles.map {
                ArticleListEntry(article: $0, membershipStatus: .matchesCurrentQuery)
            }
        }

        var loadedArticlesByID: [UUID: ArticleListItemDTO] = [:]
        for loadedArticle in loadedArticles where loadedArticlesByID[loadedArticle.id] == nil {
            loadedArticlesByID[loadedArticle.id] = loadedArticle
        }

        var emittedArticleIDs = Set<UUID>()
        var mergedEntries: [ArticleListEntry] = []

        for currentEntry in currentEntries {
            if let loadedArticle = loadedArticlesByID[currentEntry.id] {
                mergedEntries.append(
                    ArticleListEntry(
                        article: loadedArticle,
                        membershipStatus: .matchesCurrentQuery
                    )
                )
                emittedArticleIDs.insert(loadedArticle.id)
            } else if currentEntry.isRetained || retainedArticleIDs.contains(currentEntry.id) {
                mergedEntries.append(
                    ArticleListEntry(
                        article: currentEntry.article,
                        membershipStatus: retainedMembershipStatus
                    )
                )
                emittedArticleIDs.insert(currentEntry.id)
            }
        }

        for loadedArticle in loadedArticles where emittedArticleIDs.contains(loadedArticle.id) == false {
            mergedEntries.append(
                ArticleListEntry(
                    article: loadedArticle,
                    membershipStatus: .matchesCurrentQuery
                )
            )
        }

        return mergedEntries
    }
}

enum ArticleListEntryMembershipStatus: Equatable {
    case matchesCurrentQuery
    case retainedAfterFilterMutation
    case retainedAfterRefresh
}

struct ArticleListEntry: Identifiable, Equatable {
    let id: UUID
    let article: ArticleListItemDTO
    let membershipStatus: ArticleListEntryMembershipStatus

    init(
        article: ArticleListItemDTO,
        membershipStatus: ArticleListEntryMembershipStatus = .matchesCurrentQuery
    ) {
        self.id = article.id
        self.article = article
        self.membershipStatus = membershipStatus
    }

    func updating(
        article: ArticleListItemDTO,
        membershipStatus: ArticleListEntryMembershipStatus? = nil
    ) -> ArticleListEntry {
        ArticleListEntry(
            article: article,
            membershipStatus: membershipStatus ?? self.membershipStatus
        )
    }

    var isRetained: Bool {
        switch membershipStatus {
        case .matchesCurrentQuery:
            false
        case .retainedAfterFilterMutation, .retainedAfterRefresh:
            true
        }
    }
}
