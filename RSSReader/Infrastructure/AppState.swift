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
    case safari(ArticleSafariRoute)
}

enum ReaderAdjacentArticleNavigationDirection: Sendable {
    case previous
    case next
}

struct ReadingNavigationState: Hashable, Sendable {
    var sidebarSelection: SidebarSelection? = nil
    var articleSelection: UUID? = nil
    var detailRoute: ReadingDetailRoute = .none

    mutating func selectSidebarSelection(_ sidebarSelection: SidebarSelection?) {
        self.sidebarSelection = sidebarSelection
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
            )
        )
        return true
    }

    mutating func dismissSafari() {
        detailRoute = articleSelection.map(ReadingDetailRoute.article) ?? .none
    }
}

struct ArticleListScrollPositionKey: Hashable, Sendable {
    let sidebarSelection: SidebarSelection?
    let sidebarArticleFilter: SidebarArticleFilter
}

struct ArticleReadOnOpenEvent: Equatable, Sendable {
    let id = UUID()
    let articleID: UUID
    let sidebarSelection: SidebarSelection?
    let sidebarArticleFilter: SidebarArticleFilter
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
    var isPresentingSourceManagementScreen = false
    var sourceManagementLaunchContext: SourceManagementScreenLaunchContext = .entry
    var articleNavigationContextIDs: [UUID] = []
    private var articleNavigationContextSidebarSelection: SidebarSelection?
    private var articleNavigationContextSidebarArticleFilter: SidebarArticleFilter = .allItems
    private var articleListScrollPositionIDs: [ArticleListScrollPositionKey: UUID] = [:]
    var articleListReloadID = UUID()
    var sidebarReloadID = UUID()
    var sourceIconReloadID = UUID()
    var sourceIconCacheResetID = UUID()
    private var sourceIconNetworkLoadFeedIDs: Set<UUID> = []
    var articleScreenReloadID = UUID()
    var articleReadOnOpenEvent: ArticleReadOnOpenEvent?
    var lastContentReloadTrigger: AppContentReloadTrigger?

    var selectedSidebarSelection: SidebarSelection? {
        get { readingNavigation.sidebarSelection }
        set { selectSidebarSelection(newValue) }
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
        guard case .safari(let route) = readingNavigation.detailRoute else {
            return nil
        }
        return route
    }

    @discardableResult
    func presentSafari(articleID: UUID, url: URL) -> Bool {
        readingNavigation.presentSafari(articleID: articleID, url: url)
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

    func presentSourceManagementScreen(
        launchContext: SourceManagementScreenLaunchContext = .entry
    ) {
        sourceManagementLaunchContext = launchContext
        isPresentingSourceManagementScreen = true
    }

    func dismissSourceManagementScreen() {
        isPresentingSourceManagementScreen = false
        sourceManagementLaunchContext = .entry
    }

    func selectSidebarArticleFilter(_ filter: SidebarArticleFilter) {
        guard selectedSidebarArticleFilter != filter else {
            return
        }

        selectedSidebarArticleFilter = filter
    }

    func selectArticle(_ articleID: UUID?) {
        let previousArticleID = readingNavigation.articleSelection
        readingNavigation.selectArticle(articleID)

        guard previousArticleID != articleID else {
            return
        }

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

    func recordArticleReadOnOpenInCurrentListSession(_ articleID: UUID) {
        articleReadOnOpenEvent = ArticleReadOnOpenEvent(
            articleID: articleID,
            sidebarSelection: selectedSidebarSelection,
            sidebarArticleFilter: selectedSidebarArticleFilter
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

    func requestSourceIconReload() {
        sourceIconReloadID = UUID()
    }

    func requestSourceIconNetworkLoad(for feedID: UUID) {
        sourceIconNetworkLoadFeedIDs.insert(feedID)
    }

    func consumeSourceIconNetworkLoadRequest(for feedID: UUID) -> Bool {
        sourceIconNetworkLoadFeedIDs.remove(feedID) != nil
    }

    func requestSourceIconCacheReset() {
        sourceIconCacheResetID = UUID()
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

    func selectSidebarSelection(_ sidebarSelection: SidebarSelection?) {
        let previousSidebarSelection = readingNavigation.sidebarSelection
        guard previousSidebarSelection != sidebarSelection else { return }

        readingNavigation.selectSidebarSelection(sidebarSelection)
        clearArticleNavigationContext()
        requestArticleListReload()
    }

    func updateArticleNavigationContext(_ articleIDs: [UUID]) {
        updateArticleNavigationContext(
            articleIDs,
            sidebarSelection: selectedSidebarSelection,
            sidebarArticleFilter: selectedSidebarArticleFilter
        )
    }

    func updateArticleNavigationContext(
        _ articleIDs: [UUID],
        sidebarSelection: SidebarSelection?,
        sidebarArticleFilter: SidebarArticleFilter
    ) {
        var seenArticleIDs = Set<UUID>()
        articleNavigationContextSidebarSelection = sidebarSelection
        articleNavigationContextSidebarArticleFilter = sidebarArticleFilter
        articleNavigationContextIDs = articleIDs.filter { articleID in
            seenArticleIDs.insert(articleID).inserted
        }
    }

    private func clearArticleNavigationContext() {
        articleNavigationContextIDs = []
        articleNavigationContextSidebarSelection = selectedSidebarSelection
        articleNavigationContextSidebarArticleFilter = selectedSidebarArticleFilter
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
