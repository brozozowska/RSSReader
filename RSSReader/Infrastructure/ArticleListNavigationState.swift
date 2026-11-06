import Foundation

struct ArticleListScrollPositionKey: Hashable, Sendable {
    let sidebarSelection: SidebarSelection?
    let sidebarArticleFilter: SidebarArticleFilter
}

struct ArticleReadOnOpenEvent: Equatable, Sendable {
    let id = UUID()
    let articleID: UUID
    let articleListSessionID: UUID
    let sidebarSelection: SidebarSelection?
    let sidebarArticleFilter: SidebarArticleFilter
    let isRead: Bool
}

struct ArticleListSessionReference: Equatable, Sendable {
    let id: UUID
    let sidebarSelection: SidebarSelection?
    let sidebarArticleFilter: SidebarArticleFilter
}


/// Published list order/session and viewport anchors, independent of screen query lifecycles.
struct ArticleListNavigationState {
    private(set) var articleIDs: [UUID] = []
    private var context = ArticleListScrollPositionKey(sidebarSelection: nil, sidebarArticleFilter: .allItems)
    private var listSessionID: UUID?
    private var scrollPositionIDs: [ArticleListScrollPositionKey: UUID] = [:]
    private(set) var readOnOpenEvent: ArticleReadOnOpenEvent?

    var currentSessionReference: ArticleListSessionReference? {
        guard let listSessionID else { return nil }
        return ArticleListSessionReference(
            id: listSessionID,
            sidebarSelection: context.sidebarSelection,
            sidebarArticleFilter: context.sidebarArticleFilter
        )
    }

    mutating func updateContext(
        _ articleIDs: [UUID],
        sidebarSelection: SidebarSelection?,
        sidebarArticleFilter: SidebarArticleFilter,
        articleListSessionID: UUID?
    ) {
        context = ArticleListScrollPositionKey(
            sidebarSelection: sidebarSelection,
            sidebarArticleFilter: sidebarArticleFilter
        )
        listSessionID = articleListSessionID
        var seen = Set<UUID>()
        self.articleIDs = articleIDs.filter { seen.insert($0).inserted }
    }

    mutating func clearContext(sidebarSelection: SidebarSelection?, sidebarArticleFilter: SidebarArticleFilter) {
        updateContext([], sidebarSelection: sidebarSelection, sidebarArticleFilter: sidebarArticleFilter, articleListSessionID: nil)
    }

    mutating func recordReadOnOpen(_ articleID: UUID, isRead: Bool, in session: ArticleListSessionReference) {
        // Preserve the originating session even after navigation. The receiving
        // screen rejects stale/repeated events against its own active session.
        readOnOpenEvent = ArticleReadOnOpenEvent(
            articleID: articleID,
            articleListSessionID: session.id,
            sidebarSelection: session.sidebarSelection,
            sidebarArticleFilter: session.sidebarArticleFilter,
            isRead: isRead
        )
    }

    func scrollPositionID(sidebarSelection: SidebarSelection?, sidebarArticleFilter: SidebarArticleFilter) -> UUID? {
        scrollPositionIDs[ArticleListScrollPositionKey(
            sidebarSelection: sidebarSelection, sidebarArticleFilter: sidebarArticleFilter
        )]
    }

    mutating func updateScrollPosition(
        _ articleID: UUID?,
        sidebarSelection: SidebarSelection?,
        sidebarArticleFilter: SidebarArticleFilter,
        detailRoute: ReadingDetailRoute
    ) {
        guard case .none = detailRoute else { return }
        setScrollPosition(articleID, sidebarSelection: sidebarSelection, sidebarArticleFilter: sidebarArticleFilter)
    }

    /// Explicit Reader navigation may update the anchor while passive updates are frozen.
    mutating func followReaderArticle(_ articleID: UUID, navigation: ReadingNavigationState) {
        setScrollPosition(articleID, sidebarSelection: navigation.sidebarSelection, sidebarArticleFilter: navigation.sidebarArticleFilter)
    }

    private mutating func setScrollPosition(
        _ articleID: UUID?, sidebarSelection: SidebarSelection?, sidebarArticleFilter: SidebarArticleFilter
    ) {
        let key = ArticleListScrollPositionKey(sidebarSelection: sidebarSelection, sidebarArticleFilter: sidebarArticleFilter)
        scrollPositionIDs[key] = articleID
    }

    func adjacentArticleIDs(
        _ direction: ReaderAdjacentArticleNavigationDirection,
        limit: Int,
        navigation: ReadingNavigationState
    ) -> [UUID] {
        guard limit > 0,
              context.sidebarSelection == navigation.sidebarSelection,
              context.sidebarArticleFilter == navigation.sidebarArticleFilter,
              let selectedArticleID = navigation.articleSelection,
              let currentIndex = articleIDs.firstIndex(of: selectedArticleID) else { return [] }

        let step = direction == .previous ? -1 : 1
        var result: [UUID] = []
        var targetIndex = currentIndex + step
        while articleIDs.indices.contains(targetIndex), result.count < limit {
            result.append(articleIDs[targetIndex])
            targetIndex += step
        }
        return result
    }
}
