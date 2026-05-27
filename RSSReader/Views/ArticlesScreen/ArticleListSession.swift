import Foundation

struct ArticleListSession: Equatable {
    struct Context: Equatable {
        let selection: SidebarSelection?
        let sourcesFilter: SourcesFilter

        var articleListFilter: ArticleListFilter {
            ArticlesScreenMutationReducer.articleListFilter(
                selection: selection,
                sourcesFilter: sourcesFilter
            )
        }

        static let noSelection = Context(selection: nil, sourcesFilter: .allItems)
    }

    private(set) var context: Context
    private(set) var entries: [ArticleListEntry]

    var articles: [ArticleListItemDTO] {
        entries.map(\.article)
    }

    init(context: Context, entries: [ArticleListEntry] = []) {
        self.context = context
        self.entries = entries
    }

    init(context: Context, articles: [ArticleListItemDTO]) {
        self.init(
            context: context,
            entries: articles.map { ArticleListEntry(article: $0) }
        )
    }

    mutating func replaceArticles(
        _ articles: [ArticleListItemDTO],
        context: Context
    ) {
        replaceEntries(
            articles.map { ArticleListEntry(article: $0) },
            context: context
        )
    }

    mutating func replaceEntries(
        _ entries: [ArticleListEntry],
        context: Context
    ) {
        self.context = context
        self.entries = entries
    }

    mutating func updateArticle(_ article: ArticleListItemDTO) {
        entries = entries.map { entry in
            entry.id == article.id ? entry.updating(article: article) : entry
        }
    }

    mutating func removeArticle(id articleID: UUID) {
        entries.removeAll { $0.id == articleID }
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
                        membershipStatus: currentEntry.retainedMembershipStatus(
                            fallback: retainedMembershipStatus
                        )
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
    case retainedAfterRead
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

    func updating(article: ArticleListItemDTO) -> ArticleListEntry {
        ArticleListEntry(
            article: article,
            membershipStatus: membershipStatus
        )
    }

    var isRetained: Bool {
        switch membershipStatus {
        case .matchesCurrentQuery:
            false
        case .retainedAfterRead, .retainedAfterRefresh:
            true
        }
    }

    func retainedMembershipStatus(
        fallback: ArticleListEntryMembershipStatus
    ) -> ArticleListEntryMembershipStatus {
        isRetained ? membershipStatus : fallback
    }
}
