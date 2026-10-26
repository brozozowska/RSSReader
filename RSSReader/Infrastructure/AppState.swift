import Foundation
import Observation

@Observable
public final class AppState {
    private(set) var readingNavigation = ReadingNavigationState()
    private(set) var presentation = AppPresentationState()
    private(set) var confirmations = AppConfirmationState()
    private(set) var reload = AppReloadState()
    private(set) var runtime = AppRuntimeState()
    private(set) var articleListNavigation = ArticleListNavigationState()

    var selectedSidebarArticleFilter: SidebarArticleFilter { readingNavigation.sidebarArticleFilter }
    var interfaceThemeMode: InterfaceThemeMode { runtime.interfaceThemeMode }
    var iCloudSyncStatus: ICloudSyncStatus { runtime.iCloudSyncStatus }
    var isPresentingSettingsScreen: Bool { presentation.isPresentingSettingsScreen }
    var isPresentingFeedManagementScreen: Bool { presentation.isPresentingFeedManagementScreen }
    var feedManagementLaunchContext: FeedManagementScreenLaunchContext { presentation.feedManagementLaunchContext }
    var articleNavigationContextIDs: [UUID] { articleListNavigation.articleIDs }
    var articleListReloadID: UUID { reload.articleListReloadID }
    var sidebarReloadID: UUID { reload.sidebarReloadID }
    var feedIconCacheResetID: UUID { reload.feedIconCacheResetID }
    var articleScreenReloadID: UUID { reload.articleScreenReloadID }
    var articleReadOnOpenEvent: ArticleReadOnOpenEvent? { articleListNavigation.readOnOpenEvent }
    var lastContentReloadTrigger: AppContentReloadTrigger? { reload.lastContentReloadTrigger }
    var pendingFeedUnsubscribeConfirmation: PendingFeedUnsubscribeConfirmation? { confirmations.pendingFeedUnsubscribeConfirmation }
    var pendingFolderDeleteConfirmation: PendingFolderDeleteConfirmation? { confirmations.pendingFolderDeleteConfirmation }

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

    var isArticleListCoveredByDetailRoute: Bool {
        if case .none = selectedDetailRoute {
            return false
        }
        return true
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
        presentation.presentSettingsScreen()
    }

    func dismissSettingsScreen() {
        presentation.dismissSettingsScreen()
    }

    func presentFeedManagementScreen(
        launchContext: FeedManagementScreenLaunchContext = .entry
    ) {
        presentation.presentFeedManagementScreen(launchContext: launchContext)
    }

    func dismissFeedManagementScreen() {
        presentation.dismissFeedManagementScreen()
    }

    func selectSidebarArticleFilter(_ filter: SidebarArticleFilter) {
        guard selectedSidebarArticleFilter != filter else { return }
        readingNavigation.selectSidebarArticleFilter(filter)
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
        runtime.applyInterfaceThemeMode(mode)
    }

    func applyICloudSyncStatus(_ status: ICloudSyncStatus) {
        runtime.applyICloudSyncStatus(status)
    }

    func requestArticleListReload() {
        reload.requestArticleListReload()
    }

    var currentArticleListSessionReference: ArticleListSessionReference? {
        articleListNavigation.currentSessionReference
    }

    func recordArticleReadOnOpen(
        _ articleID: UUID,
        isRead: Bool,
        in listSession: ArticleListSessionReference
    ) {
        articleListNavigation.recordReadOnOpen(articleID, isRead: isRead, in: listSession)
    }

    func articleListScrollPositionID(
        sidebarSelection: SidebarSelection?,
        sidebarArticleFilter: SidebarArticleFilter
    ) -> UUID? {
        articleListNavigation.scrollPositionID(sidebarSelection: sidebarSelection, sidebarArticleFilter: sidebarArticleFilter)
    }

    func updateArticleListScrollPosition(
        _ articleID: UUID?,
        sidebarSelection: SidebarSelection?,
        sidebarArticleFilter: SidebarArticleFilter
    ) {
        articleListNavigation.updateScrollPosition(
            articleID, sidebarSelection: sidebarSelection, sidebarArticleFilter: sidebarArticleFilter,
            detailRoute: selectedDetailRoute
        )
    }

    func requestSidebarReload() {
        reload.requestSidebarReload()
    }

    func requestFeedIconCacheReset() {
        reload.requestFeedIconCacheReset()
    }

    func requestArticleScreenReload() {
        reload.requestArticleScreenReload()
    }

    func requestRemoteSyncImportReload() {
        reload.requestContentReload(.remoteSyncImport)
    }

    func requestBackgroundRefreshReload() {
        reload.requestContentReload(.backgroundRefresh)
    }

    func presentFeedUnsubscribeConfirmation(feedID: UUID, feedTitle: String) {
        confirmations.presentFeedUnsubscribeConfirmation(feedID: feedID, feedTitle: feedTitle)
    }

    func dismissFeedUnsubscribeConfirmation() {
        confirmations.dismissFeedUnsubscribeConfirmation()
    }

    func presentFolderDeleteConfirmation(folderName: String) {
        confirmations.presentFolderDeleteConfirmation(folderName: folderName)
    }

    func dismissFolderDeleteConfirmation() {
        confirmations.dismissFolderDeleteConfirmation()
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
            articleListSessionID: articleListNavigation.currentSessionReference?.id
        )
    }

    func updateArticleNavigationContext(
        _ articleIDs: [UUID],
        sidebarSelection: SidebarSelection?,
        sidebarArticleFilter: SidebarArticleFilter,
        articleListSessionID: UUID? = nil
    ) {
        articleListNavigation.updateContext(
            articleIDs, sidebarSelection: sidebarSelection, sidebarArticleFilter: sidebarArticleFilter,
            articleListSessionID: articleListSessionID
        )
    }

    private func clearArticleNavigationContext() {
        articleListNavigation.clearContext(
            sidebarSelection: selectedSidebarSelection, sidebarArticleFilter: selectedSidebarArticleFilter
        )
    }

    @discardableResult
    func selectAdjacentArticle(_ direction: ReaderAdjacentArticleNavigationDirection) -> Bool {
        guard let targetArticleID = adjacentArticleID(direction) else {
            return false
        }

        selectArticle(targetArticleID)
        articleListNavigation.followReaderArticle(targetArticleID, navigation: readingNavigation)
        return true
    }

    func adjacentArticleID(_ direction: ReaderAdjacentArticleNavigationDirection) -> UUID? {
        adjacentArticleIDs(direction, limit: 1).first
    }

    func adjacentArticleIDs(
        _ direction: ReaderAdjacentArticleNavigationDirection,
        limit: Int
    ) -> [UUID] {
        articleListNavigation.adjacentArticleIDs(direction, limit: limit, navigation: readingNavigation)
    }

    public init() {}
}
