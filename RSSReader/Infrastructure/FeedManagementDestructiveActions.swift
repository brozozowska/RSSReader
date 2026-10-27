import Foundation

/// App-level orchestration; persistence and business rules remain in the injected services.
@MainActor
struct FeedManagementDestructiveActions {
    private let logger: Logging
    private let folderRepository: (any FolderRepository)?
    private let feedManagementService: (any FeedManagementService)?
    private let scheduleUnreadAppIconBadgeRefresh: @MainActor () -> Void

    init(
        logger: Logging,
        folderRepository: (any FolderRepository)?,
        feedManagementService: (any FeedManagementService)?,
        scheduleUnreadAppIconBadgeRefresh: @escaping @MainActor () -> Void
    ) {
        self.logger = logger
        self.folderRepository = folderRepository
        self.feedManagementService = feedManagementService
        self.scheduleUnreadAppIconBadgeRefresh = scheduleUnreadAppIconBadgeRefresh
    }

    func finishUnsubscribingFeed(id feedID: UUID, using appState: AppState) {
        appState.requestSidebarReload()
        if appState.selectedSidebarSelection == .feed(feedID) {
            appState.reconcileSidebarSelection(
                .inbox,
                expectedSelection: .feed(feedID),
                expectedFilter: appState.selectedSidebarArticleFilter
            )
        } else {
            appState.requestArticleListReload()
        }
    }

    func requestFeedUnsubscribeConfirmation(
        id feedID: UUID,
        title feedTitle: String,
        using appState: AppState
    ) {
        appState.presentFeedUnsubscribeConfirmation(
            feedID: feedID,
            feedTitle: feedTitle
        )
    }

    func cancelFeedUnsubscribeConfirmation(using appState: AppState) {
        appState.dismissFeedUnsubscribeConfirmation()
    }

    func confirmPendingFeedUnsubscribe(using appState: AppState) {
        guard let pendingConfirmation = appState.confirmations.pendingFeedUnsubscribeConfirmation else {
            return
        }

        appState.dismissFeedUnsubscribeConfirmation()
        unsubscribeFeed(id: pendingConfirmation.feedID, using: appState)
    }

    func requestFolderDeleteConfirmation(
        named folderName: String,
        using appState: AppState
    ) {
        appState.presentFolderDeleteConfirmation(folderName: folderName)
    }

    func cancelFolderDeleteConfirmation(using appState: AppState) {
        appState.dismissFolderDeleteConfirmation()
    }

    func confirmPendingFolderDelete(using appState: AppState) {
        guard let pendingConfirmation = appState.confirmations.pendingFolderDeleteConfirmation else {
            return
        }

        appState.dismissFolderDeleteConfirmation()
        deleteFolder(named: pendingConfirmation.folderName, using: appState)
    }

    func finishDeletingFolder(named folderName: String, using appState: AppState) {
        appState.requestSidebarReload()
        if appState.selectedSidebarSelection == .folder(folderName) {
            appState.reconcileSidebarSelection(
                .inbox,
                expectedSelection: .folder(folderName),
                expectedFilter: appState.selectedSidebarArticleFilter
            )
        } else {
            appState.requestArticleListReload()
        }
    }

    func unsubscribeFeed(id feedID: UUID, using appState: AppState) {
        guard let feedManagementService else {
            logger.error("Feed management service is unavailable for feed deletion")
            return
        }

        do {
            try feedManagementService.deleteFeed(id: feedID)
            finishUnsubscribingFeed(id: feedID, using: appState)
            scheduleUnreadAppIconBadgeRefresh()
        } catch {
            logger.error("Failed to unsubscribe feed \(feedID): \(error)")
        }
    }

    func deleteFolder(named folderName: String, using appState: AppState) {
        guard let folderRepository else {
            logger.error("Folder repository is unavailable for folder deletion")
            return
        }
        guard let feedManagementService else {
            logger.error("Feed management service is unavailable for folder deletion")
            return
        }

        do {
            guard let folder = try folderRepository.fetchFolder(name: folderName) else {
                logger.error("Skipped folder deletion because folder \(folderName) was not found")
                return
            }
            try feedManagementService.deleteFolder(id: folder.id)
            finishDeletingFolder(named: folderName, using: appState)
        } catch {
            logger.error("Failed to delete folder \(folderName): \(error)")
        }
    }
}
