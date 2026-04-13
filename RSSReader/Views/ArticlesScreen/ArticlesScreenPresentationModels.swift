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
