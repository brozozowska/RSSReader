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

struct ArticleSafariRoute: Hashable, Sendable {
    let articleID: UUID
    let url: URL
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
    var sourceSelection: SourceSelection? = nil
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

    mutating func presentSafari(articleID: UUID, url: URL) {
        articleSelection = articleID
        detailRoute = .safari(
            ArticleSafariRoute(
                articleID: articleID,
                url: url
            )
        )
    }

    mutating func dismissSafari() {
        detailRoute = articleSelection.map(ReadingDetailRoute.article) ?? .none
    }
}

enum AppContentReloadTrigger: Equatable, Sendable {
    case remoteSyncImport
    case backgroundRefresh
}

@Observable
public final class AppState {
    var readingNavigation = ReadingNavigationState()
    var selectedSourcesFilter: SourcesFilter = .allItems
    var interfaceThemeMode: InterfaceThemeMode = .automaticLightDark
    var iCloudSyncStatus: ICloudSyncStatus = .disabled
    var isPresentingSettingsScreen = false
    var isPresentingSourceManagementScreen = false
    var sourceManagementLaunchContext: SourceManagementScreenLaunchContext = .entry
    var articleNavigationContextIDs: [UUID] = []
    var articleListReloadID = UUID()
    var sourcesSidebarReloadID = UUID()
    var articleScreenReloadID = UUID()
    var lastContentReloadTrigger: AppContentReloadTrigger?

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

    var presentedSafariRoute: ArticleSafariRoute? {
        guard case .safari(let route) = readingNavigation.detailRoute else {
            return nil
        }
        return route
    }

    func presentSafari(articleID: UUID, url: URL) {
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

    func selectSourcesFilter(_ filter: SourcesFilter) {
        selectedSourcesFilter = filter
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

    func requestSourcesSidebarReload() {
        sourcesSidebarReloadID = UUID()
    }

    func requestArticleScreenReload() {
        articleScreenReloadID = UUID()
    }

    func requestRemoteSyncImportReload() {
        lastContentReloadTrigger = .remoteSyncImport
        requestSourcesSidebarReload()
        requestArticleListReload()
        requestArticleScreenReload()
    }

    func requestBackgroundRefreshReload() {
        lastContentReloadTrigger = .backgroundRefresh
        requestSourcesSidebarReload()
        requestArticleListReload()
        requestArticleScreenReload()
    }

    func selectReadingSource(_ sourceSelection: SourceSelection?) {
        let previousSourceSelection = readingNavigation.sourceSelection
        guard previousSourceSelection != sourceSelection else { return }

        readingNavigation.selectSource(sourceSelection)
        articleNavigationContextIDs = []
        requestArticleListReload()
    }

    func updateArticleNavigationContext(_ articleIDs: [UUID]) {
        articleNavigationContextIDs = articleIDs
    }

    @discardableResult
    func selectAdjacentArticle(_ direction: ReaderAdjacentArticleNavigationDirection) -> Bool {
        guard let selectedArticleID,
              let currentIndex = articleNavigationContextIDs.firstIndex(of: selectedArticleID) else {
            return false
        }

        let targetIndex: Int
        switch direction {
        case .previous:
            targetIndex = currentIndex - 1
        case .next:
            targetIndex = currentIndex + 1
        }

        guard articleNavigationContextIDs.indices.contains(targetIndex) else {
            return false
        }

        self.selectedArticleID = articleNavigationContextIDs[targetIndex]
        return true
    }

    public init() {}
}
