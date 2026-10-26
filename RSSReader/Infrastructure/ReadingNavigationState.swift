import Foundation

enum SidebarSelection: Hashable, Sendable {
    case inbox
    case unread
    case starred
    case folder(String)
    case feed(UUID)
}

enum SidebarArticleFilter: String, Hashable, Sendable, CaseIterable {
    case allItems
    case unread
    case starred
}

enum ManualFeedRefreshScope: Equatable, Sendable {
    case allFeeds
    case folder(String)
    case feed(UUID)
}

struct ManualFeedRefreshContext: Equatable, Sendable {
    let selection: SidebarSelection?
    let sidebarArticleFilter: SidebarArticleFilter

    var scope: ManualFeedRefreshScope {
        switch selection {
        case .feed(let feedID):
            .feed(feedID)
        case .folder(let folderName):
            .folder(folderName)
        case .inbox, .unread, .starred, .none:
            .allFeeds
        }
    }
}
struct ArticleSafariRoute: Hashable, Sendable {
    let articleID: UUID
    let url: URL

    static func canOpen(_ url: URL) -> Bool {
        guard let scheme = url.scheme else {
            return false
        }
        let normalizedScheme = scheme.lowercased()
        guard normalizedScheme == "http" || normalizedScheme == "https" else {
            return false
        }
        return url.host?.isEmpty == false
    }
}

enum ReadingDetailRoute: Hashable, Sendable {
    case none
    case article(UUID)
    case safari(ArticleSafariRoute, dismissalTarget: ArticleSafariDismissalTarget)
}

enum ArticleSafariDismissalTarget: Hashable, Sendable {
    case article
    case articleList
}

enum ReaderAdjacentArticleNavigationDirection: Equatable, Sendable {
    case previous
    case next
}

struct ReadingNavigationState: Hashable, Sendable {
    private(set) var sidebarSelection: SidebarSelection? = nil
    private(set) var presentedSidebarSelection: SidebarSelection? = nil
    private(set) var articleSelection: UUID? = nil
    private(set) var detailRoute: ReadingDetailRoute = .none

    private(set) var sidebarArticleFilter: SidebarArticleFilter = .allItems

    mutating func selectSidebarArticleFilter(_ filter: SidebarArticleFilter) {
        guard sidebarArticleFilter != filter else { return }
        sidebarArticleFilter = filter
    }

    mutating func selectSidebarSelection(_ sidebarSelection: SidebarSelection?) {
        presentedSidebarSelection = sidebarSelection
        guard self.sidebarSelection != sidebarSelection else { return }

        self.sidebarSelection = sidebarSelection
        articleSelection = nil
        detailRoute = .none
    }

    mutating func dismissSidebarSelectionPresentation() {
        presentedSidebarSelection = nil
    }

    mutating func reconcileSidebarSelection(_ sidebarSelection: SidebarSelection?) {
        guard self.sidebarSelection != sidebarSelection else { return }

        let preservesPresentation = presentedSidebarSelection != nil
        self.sidebarSelection = sidebarSelection
        presentedSidebarSelection = preservesPresentation ? sidebarSelection : nil
        articleSelection = nil
        detailRoute = .none
    }

    mutating func selectArticle(_ articleID: UUID?) {
        articleSelection = articleID
        detailRoute = articleID.map(ReadingDetailRoute.article) ?? .none
    }

    @discardableResult
    mutating func presentSafari(articleID: UUID, url: URL) -> Bool {
        guard ArticleSafariRoute.canOpen(url) else {
            return false
        }

        articleSelection = articleID
        detailRoute = .safari(
            ArticleSafariRoute(
                articleID: articleID,
                url: url
            ),
            dismissalTarget: .article
        )
        return true
    }

    @discardableResult
    mutating func presentSafariFromArticleList(articleID: UUID, url: URL) -> Bool {
        guard ArticleSafariRoute.canOpen(url) else {
            return false
        }

        articleSelection = nil
        detailRoute = .safari(
            ArticleSafariRoute(
                articleID: articleID,
                url: url
            ),
            dismissalTarget: .articleList
        )
        return true
    }

    mutating func dismissSafari() {
        guard case .safari(_, let dismissalTarget) = detailRoute else {
            return
        }

        switch dismissalTarget {
        case .article:
            detailRoute = articleSelection.map(ReadingDetailRoute.article) ?? .none
        case .articleList:
            articleSelection = nil
            detailRoute = .none
        }
    }
}
