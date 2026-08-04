import Foundation
import Observation

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
    var sidebarSelection: SidebarSelection? = nil
    var presentedSidebarSelection: SidebarSelection? = nil
    var articleSelection: UUID? = nil
    var detailRoute: ReadingDetailRoute = .none

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

struct PendingFeedUnsubscribeConfirmation: Identifiable, Equatable, Sendable {
    let feedID: UUID
    let feedTitle: String

    var id: UUID { feedID }
}

struct PendingFolderDeleteConfirmation: Identifiable, Equatable, Sendable {
    let folderName: String

    var id: String { folderName }
}

enum AppContentReloadTrigger: Equatable, Sendable {
    case remoteSyncImport
    case backgroundRefresh
}

@Observable
public final class AppState {
    var readingNavigation = ReadingNavigationState()
    var selectedSidebarArticleFilter: SidebarArticleFilter = .allItems
    var interfaceThemeMode: InterfaceThemeMode = .automaticLightDark
    var iCloudSyncStatus: ICloudSyncStatus = .disabled
    var isPresentingSettingsScreen = false
    var isPresentingFeedManagementScreen = false
    var feedManagementLaunchContext: FeedManagementScreenLaunchContext = .entry
    var articleNavigationContextIDs: [UUID] = []
    private var articleNavigationContextSidebarSelection: SidebarSelection?
    private var articleNavigationContextSidebarArticleFilter: SidebarArticleFilter = .allItems
    private var articleNavigationContextListSessionID: UUID?
    private var articleListScrollPositionIDs: [ArticleListScrollPositionKey: UUID] = [:]
    var articleListReloadID = UUID()
    var sidebarReloadID = UUID()
    var feedIconCacheResetID = UUID()
    var articleScreenReloadID = UUID()
    var articleReadOnOpenEvent: ArticleReadOnOpenEvent?
    var lastContentReloadTrigger: AppContentReloadTrigger?
    var pendingFeedUnsubscribeConfirmation: PendingFeedUnsubscribeConfirmation?
    var pendingFolderDeleteConfirmation: PendingFolderDeleteConfirmation?

    var selectedSidebarSelection: SidebarSelection? {
        get { readingNavigation.sidebarSelection }
        set { selectSidebarSelection(newValue) }
    }

    var presentedSidebarSelection: SidebarSelection? {
        get { readingNavigation.presentedSidebarSelection }
        set { updatePresentedSidebarSelection(newValue) }
    }

    public var selectedFeedID: UUID? {
        get {
            guard case .feed(let feedID) = readingNavigation.sidebarSelection else {
                return nil
            }
            return feedID
        }
        set {
            if let newValue {
                selectSidebarSelection(.feed(newValue))
            } else {
                selectSidebarSelection(nil)
            }
        }
    }

    public var selectedArticleID: UUID? {
        get { readingNavigation.articleSelection }
        set { selectArticle(newValue) }
    }

    var selectedDetailRoute: ReadingDetailRoute {
        readingNavigation.detailRoute
    }

    var presentedSafariRoute: ArticleSafariRoute? {
        guard case .safari(let route, _) = readingNavigation.detailRoute else {
            return nil
        }
        return route
    }

    @discardableResult
    func presentSafari(articleID: UUID, url: URL) -> Bool {
        readingNavigation.presentSafari(articleID: articleID, url: url)
    }

    @discardableResult
    func presentSafariFromArticleList(articleID: UUID, url: URL) -> Bool {
        readingNavigation.presentSafariFromArticleList(articleID: articleID, url: url)
    }

    func dismissPresentedSafari() {
        readingNavigation.dismissSafari()
    }

    func presentSettingsScreen() {
        isPresentingSettingsScreen = true
    }

    func dismissSettingsScreen() {
        isPresentingSettingsScreen = false
    }

    func presentFeedManagementScreen(
        launchContext: FeedManagementScreenLaunchContext = .entry
    ) {
        feedManagementLaunchContext = launchContext
        isPresentingFeedManagementScreen = true
    }

    func dismissFeedManagementScreen() {
        isPresentingFeedManagementScreen = false
        feedManagementLaunchContext = .entry
    }

    func selectSidebarArticleFilter(_ filter: SidebarArticleFilter) {
        guard selectedSidebarArticleFilter != filter else {
            return
        }

        selectedSidebarArticleFilter = filter
    }

    func selectArticle(_ articleID: UUID?) {
        let previousArticleID = readingNavigation.articleSelection
        guard previousArticleID != articleID else {
            return
        }

        readingNavigation.selectArticle(articleID)
        requestArticleScreenReload()
    }

    func applyInterfaceThemeMode(_ mode: InterfaceThemeMode) {
        interfaceThemeMode = mode
    }

    func applyICloudSyncStatus(_ status: ICloudSyncStatus) {
        iCloudSyncStatus = status
    }

    func requestArticleListReload() {
        articleListReloadID = UUID()
    }

    var currentArticleListSessionReference: ArticleListSessionReference? {
        guard let articleNavigationContextListSessionID else { return nil }

        return ArticleListSessionReference(
            id: articleNavigationContextListSessionID,
            sidebarSelection: articleNavigationContextSidebarSelection,
            sidebarArticleFilter: articleNavigationContextSidebarArticleFilter
        )
    }

    func recordArticleReadOnOpen(
        _ articleID: UUID,
        isRead: Bool,
        in listSession: ArticleListSessionReference
    ) {
        articleReadOnOpenEvent = ArticleReadOnOpenEvent(
            articleID: articleID,
            articleListSessionID: listSession.id,
            sidebarSelection: listSession.sidebarSelection,
            sidebarArticleFilter: listSession.sidebarArticleFilter,
            isRead: isRead
        )
    }

    func articleListScrollPositionID(
        sidebarSelection: SidebarSelection?,
        sidebarArticleFilter: SidebarArticleFilter
    ) -> UUID? {
        articleListScrollPositionIDs[
            ArticleListScrollPositionKey(
                sidebarSelection: sidebarSelection,
                sidebarArticleFilter: sidebarArticleFilter
            )
        ]
    }

    func updateArticleListScrollPosition(
        _ articleID: UUID?,
        sidebarSelection: SidebarSelection?,
        sidebarArticleFilter: SidebarArticleFilter
    ) {
        let key = ArticleListScrollPositionKey(
            sidebarSelection: sidebarSelection,
            sidebarArticleFilter: sidebarArticleFilter
        )

        if let articleID {
            articleListScrollPositionIDs[key] = articleID
        } else {
            articleListScrollPositionIDs.removeValue(forKey: key)
        }
    }

    func requestSidebarReload() {
        sidebarReloadID = UUID()
    }

    func requestFeedIconCacheReset() {
        feedIconCacheResetID = UUID()
    }

    func requestArticleScreenReload() {
        articleScreenReloadID = UUID()
    }

    func requestRemoteSyncImportReload() {
        lastContentReloadTrigger = .remoteSyncImport
        requestSidebarReload()
        requestArticleListReload()
        requestArticleScreenReload()
    }

    func requestBackgroundRefreshReload() {
        lastContentReloadTrigger = .backgroundRefresh
        requestSidebarReload()
        requestArticleListReload()
        requestArticleScreenReload()
    }

    func presentFeedUnsubscribeConfirmation(feedID: UUID, feedTitle: String) {
        pendingFolderDeleteConfirmation = nil
        pendingFeedUnsubscribeConfirmation = PendingFeedUnsubscribeConfirmation(
            feedID: feedID,
            feedTitle: feedTitle
        )
    }

    func dismissFeedUnsubscribeConfirmation() {
        pendingFeedUnsubscribeConfirmation = nil
    }

    func presentFolderDeleteConfirmation(folderName: String) {
        pendingFeedUnsubscribeConfirmation = nil
        pendingFolderDeleteConfirmation = PendingFolderDeleteConfirmation(
            folderName: folderName
        )
    }

    func dismissFolderDeleteConfirmation() {
        pendingFolderDeleteConfirmation = nil
    }

    func selectSidebarSelection(_ sidebarSelection: SidebarSelection?) {
        let previousSidebarSelection = readingNavigation.sidebarSelection
        readingNavigation.selectSidebarSelection(sidebarSelection)
        guard previousSidebarSelection != sidebarSelection else { return }

        clearArticleNavigationContext()
        requestArticleListReload()
    }

    func updatePresentedSidebarSelection(_ sidebarSelection: SidebarSelection?) {
        guard let sidebarSelection else {
            readingNavigation.dismissSidebarSelectionPresentation()
            clearArticleNavigationContext()
            return
        }

        selectSidebarSelection(sidebarSelection)
    }

    @discardableResult
    func reconcileSidebarSelection(
        _ sidebarSelection: SidebarSelection?,
        expectedSelection: SidebarSelection?,
        expectedFilter: SidebarArticleFilter
    ) -> Bool {
        guard selectedSidebarSelection == expectedSelection,
              selectedSidebarArticleFilter == expectedFilter else {
            return false
        }

        let previousSidebarSelection = readingNavigation.sidebarSelection
        readingNavigation.reconcileSidebarSelection(sidebarSelection)
        guard previousSidebarSelection != sidebarSelection else { return true }

        clearArticleNavigationContext()
        requestArticleListReload()
        return true
    }

    func updateArticleNavigationContext(_ articleIDs: [UUID]) {
        updateArticleNavigationContext(
            articleIDs,
            sidebarSelection: selectedSidebarSelection,
            sidebarArticleFilter: selectedSidebarArticleFilter,
            articleListSessionID: articleNavigationContextListSessionID
        )
    }

    func updateArticleNavigationContext(
        _ articleIDs: [UUID],
        sidebarSelection: SidebarSelection?,
        sidebarArticleFilter: SidebarArticleFilter,
        articleListSessionID: UUID? = nil
    ) {
        var seenArticleIDs = Set<UUID>()
        articleNavigationContextSidebarSelection = sidebarSelection
        articleNavigationContextSidebarArticleFilter = sidebarArticleFilter
        articleNavigationContextListSessionID = articleListSessionID
        articleNavigationContextIDs = articleIDs.filter { articleID in
            seenArticleIDs.insert(articleID).inserted
        }
    }

    private func clearArticleNavigationContext() {
        articleNavigationContextIDs = []
        articleNavigationContextSidebarSelection = selectedSidebarSelection
        articleNavigationContextSidebarArticleFilter = selectedSidebarArticleFilter
        articleNavigationContextListSessionID = nil
    }

    @discardableResult
    func selectAdjacentArticle(_ direction: ReaderAdjacentArticleNavigationDirection) -> Bool {
        guard let targetArticleID = adjacentArticleID(direction) else {
            return false
        }

        selectArticle(targetArticleID)
        return true
    }

    func adjacentArticleID(_ direction: ReaderAdjacentArticleNavigationDirection) -> UUID? {
        guard articleNavigationContextSidebarSelection == selectedSidebarSelection,
              articleNavigationContextSidebarArticleFilter == selectedSidebarArticleFilter else {
            return nil
        }

        guard let selectedArticleID,
              let currentIndex = articleNavigationContextIDs.firstIndex(of: selectedArticleID) else {
            return nil
        }

        let step: Int
        switch direction {
        case .previous:
            step = -1
        case .next:
            step = 1
        }

        var targetIndex = currentIndex + step
        while articleNavigationContextIDs.indices.contains(targetIndex) {
            let targetArticleID = articleNavigationContextIDs[targetIndex]
            if targetArticleID != selectedArticleID {
                return targetArticleID
            }

            targetIndex += step
        }

        return nil
    }

    public init() {}
}
