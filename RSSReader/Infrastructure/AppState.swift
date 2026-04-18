import Foundation
import Observation

enum SourceSelection: Hashable, Sendable {
    case inbox
    case unread
    case starred
    case folder(String)
    case feed(UUID)
}

enum SourcesFilter: String, Hashable, Sendable, CaseIterable {
    case allItems
    case unread
    case starred
}

typealias SidebarSelection = SourceSelection

struct ArticleWebViewRoute: Hashable, Sendable {
    let articleID: UUID
    let url: URL
}

enum ReadingDetailRoute: Hashable, Sendable {
    case none
    case article(UUID)
    case webView(ArticleWebViewRoute)
}

struct ReadingNavigationState: Hashable, Sendable {
    var sourceSelection: SourceSelection? = .inbox
    var articleSelection: UUID? = nil
    var detailRoute: ReadingDetailRoute = .none

    mutating func selectSource(_ sourceSelection: SourceSelection?) {
        self.sourceSelection = sourceSelection
        articleSelection = nil
        detailRoute = .none
    }

    mutating func selectArticle(_ articleID: UUID?) {
        articleSelection = articleID
        detailRoute = articleID.map(ReadingDetailRoute.article) ?? .none
    }

    mutating func presentWebView(articleID: UUID, url: URL) {
        articleSelection = articleID
        detailRoute = .webView(
            ArticleWebViewRoute(
                articleID: articleID,
                url: url
            )
        )
    }

    mutating func dismissWebView() {
        detailRoute = articleSelection.map(ReadingDetailRoute.article) ?? .none
    }
}

@Observable
public final class AppState {
    var readingNavigation = ReadingNavigationState()
    var selectedSourcesFilter: SourcesFilter = .allItems
    var isPresentingSettingsScreen = false
    var articleListReloadID = UUID()
    var sourcesSidebarReloadID = UUID()

    var selectedSidebarSelection: SidebarSelection? {
        get { readingNavigation.sourceSelection }
        set { selectReadingSource(newValue) }
    }

    public var selectedFeedID: UUID? {
        get {
            guard case .feed(let feedID) = readingNavigation.sourceSelection else {
                return nil
            }
            return feedID
        }
        set {
            if let newValue {
                selectReadingSource(.feed(newValue))
            } else {
                selectReadingSource(nil)
            }
        }
    }

    public var selectedArticleID: UUID? {
        get { readingNavigation.articleSelection }
        set { readingNavigation.selectArticle(newValue) }
    }

    var selectedDetailRoute: ReadingDetailRoute {
        readingNavigation.detailRoute
    }

    var presentedWebViewRoute: ArticleWebViewRoute? {
        guard case .webView(let route) = readingNavigation.detailRoute else {
            return nil
        }
        return route
    }

    func presentWebView(articleID: UUID, url: URL) {
        readingNavigation.presentWebView(articleID: articleID, url: url)
    }

    func dismissPresentedWebView() {
        readingNavigation.dismissWebView()
    }

    func presentSettingsScreen() {
        isPresentingSettingsScreen = true
    }

    func dismissSettingsScreen() {
        isPresentingSettingsScreen = false
    }

    func selectSourcesFilter(_ filter: SourcesFilter) {
        selectedSourcesFilter = filter
    }

    func requestArticleListReload() {
        articleListReloadID = UUID()
    }

    func requestSourcesSidebarReload() {
        sourcesSidebarReloadID = UUID()
    }

    func selectReadingSource(_ sourceSelection: SourceSelection?) {
        let previousSourceSelection = readingNavigation.sourceSelection
        guard previousSourceSelection != sourceSelection else { return }

        readingNavigation.selectSource(sourceSelection)
        requestArticleListReload()
    }

    public init() {}
}
