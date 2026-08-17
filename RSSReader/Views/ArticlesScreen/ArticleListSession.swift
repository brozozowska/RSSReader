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
        var entriesByArticleID: [UUID: ArticleListEntry] = [:]
        for entry in entries where entriesByArticleID[entry.id] == nil {
            entriesByArticleID[entry.id] = entry
        }

        var loadedArticleIDs = Set<UUID>()
        for article in articles where loadedArticleIDs.insert(article.id).inserted {
            entriesByArticleID[article.id] = ArticleListEntry(article: article)
        }
        entries = ArticleListSessionOrderingPolicy.ordered(
            Array(entriesByArticleID.values),
            sortMode: context.sortMode
        )
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
        retainedMembershipStatus: ArticleListEntryMembershipStatus,
        sortMode: ArticleSortMode
    ) -> [ArticleListEntry] {
        var loadedArticlesByID: [UUID: ArticleListItemDTO] = [:]
        for loadedArticle in loadedArticles where loadedArticlesByID[loadedArticle.id] == nil {
            loadedArticlesByID[loadedArticle.id] = loadedArticle
        }

        guard retainsCurrentContent else {
            return ArticleListSessionOrderingPolicy.ordered(
                loadedArticlesByID.values.map {
                    ArticleListEntry(article: $0, membershipStatus: .matchesCurrentQuery)
                },
                sortMode: sortMode
            )
        }

        var mergedEntriesByID: [UUID: ArticleListEntry] = [:]

        for currentEntry in currentEntries {
            guard mergedEntriesByID[currentEntry.id] == nil,
                  currentEntry.isRetained || retainedArticleIDs.contains(currentEntry.id) else {
                continue
            }
            mergedEntriesByID[currentEntry.id] = ArticleListEntry(
                article: currentEntry.article,
                membershipStatus: retainedMembershipStatus
            )
        }

        for loadedArticle in loadedArticlesByID.values {
            mergedEntriesByID[loadedArticle.id] = ArticleListEntry(
                article: loadedArticle,
                membershipStatus: .matchesCurrentQuery
            )
        }

        return ArticleListSessionOrderingPolicy.ordered(
            Array(mergedEntriesByID.values),
            sortMode: sortMode
        )
    }
}

enum ArticleListSessionOrderingPolicy {
    static func ordered(
        _ entries: [ArticleListEntry],
        sortMode: ArticleSortMode
    ) -> [ArticleListEntry] {
        entries.sorted { lhs, rhs in
            let lhsSortDate = lhs.article.publishedAt ?? lhs.article.fetchedAt
            let rhsSortDate = rhs.article.publishedAt ?? rhs.article.fetchedAt

            if lhsSortDate != rhsSortDate {
                switch sortMode {
                case .publishedAtDescending:
                    return lhsSortDate > rhsSortDate
                case .publishedAtAscending:
                    return lhsSortDate < rhsSortDate
                }
            }

            switch sortMode {
            case .publishedAtDescending:
                return lhs.id.uuidString > rhs.id.uuidString
            case .publishedAtAscending:
                return lhs.id.uuidString < rhs.id.uuidString
            }
        }
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
