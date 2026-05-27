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
}
