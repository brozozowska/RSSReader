import Foundation

extension AppActionRouter {
    @MainActor
    private var feedManagementPresentation: FeedManagementPresentationActions {
        FeedManagementPresentationActions(
            logger: logger,
            folderRepository: folderRepository,
            feedManagementService: feedManagementService
        )
    }

    @MainActor
    private var feedManagementDestructiveActions: FeedManagementDestructiveActions {
        FeedManagementDestructiveActions(
            logger: logger,
            folderRepository: folderRepository,
            feedManagementService: feedManagementService,
            scheduleUnreadAppIconBadgeRefresh: { scheduleUnreadAppIconBadgeRefresh() }
        )
    }

    @MainActor
    func showFeedManagement(using appState: AppState) {
        feedManagementPresentation.showFeedManagement(using: appState)
    }

    @MainActor
    func showFeedEditor(id feedID: UUID, using appState: AppState) {
        feedManagementPresentation.showFeedEditor(id: feedID, using: appState)
    }

    @MainActor
    func showFeedOrganizer(id feedID: UUID, using appState: AppState) {
        feedManagementPresentation.showFeedOrganizer(id: feedID, using: appState)
    }

    @MainActor
    func showFolderEditor(named folderName: String, using appState: AppState) {
        feedManagementPresentation.showFolderEditor(named: folderName, using: appState)
    }

    @MainActor
    func loadFeedManagementAddFeedContext(
        into screenState: inout FeedManagementScreenState
    ) {
        feedManagementPresentation.loadFeedManagementAddFeedContext(into: &screenState)
    }

    @MainActor
    func loadFeedManagementAddFeedEditContext(
        feedID: UUID,
        into screenState: inout FeedManagementScreenState
    ) {
        feedManagementPresentation.loadFeedManagementAddFeedEditContext(feedID: feedID, into: &screenState)
    }

    @MainActor
    func loadFeedManagementCreateFolderContext(
        into screenState: inout FeedManagementScreenState
    ) {
        feedManagementPresentation.loadFeedManagementCreateFolderContext(into: &screenState)
    }

    @MainActor
    func loadFeedManagementCreateFolderEditContext(
        folderID: UUID,
        into screenState: inout FeedManagementScreenState
    ) {
        feedManagementPresentation.loadFeedManagementCreateFolderEditContext(folderID: folderID, into: &screenState)
    }

    @MainActor
    func loadFeedManagementMoveFeedContext(
        selectedFeedID: UUID? = nil,
        into screenState: inout FeedManagementScreenState
    ) {
        feedManagementPresentation.loadFeedManagementMoveFeedContext(selectedFeedID: selectedFeedID, into: &screenState)
    }

    @MainActor
    func restoreAddFeedAfterCreatingFolder(
        _ folder: FeedManagementFolderSummary,
        into screenState: inout FeedManagementScreenState
    ) {
        feedManagementPresentation.restoreAddFeedAfterCreatingFolder(folder, into: &screenState)
    }

    @MainActor
    func finishFolderEditing(
        previousName: String,
        updatedFolderName: String,
        using appState: AppState
    ) {
        feedManagementPresentation.finishFolderEditing(
            previousName: previousName,
            updatedFolderName: updatedFolderName,
            using: appState
        )
    }

    @MainActor
    func finishCreatingFolder(named folderName: String, using appState: AppState) {
        feedManagementPresentation.finishCreatingFolder(named: folderName, using: appState)
    }

    @MainActor
    func finishMovingFeed(
        feedID: UUID,
        previousFolderName: String?,
        updatedFolderName: String?,
        using appState: AppState
    ) {
        feedManagementPresentation.finishMovingFeed(
            feedID: feedID,
            previousFolderName: previousFolderName,
            updatedFolderName: updatedFolderName,
            using: appState
        )
    }

    @MainActor
    func finishSavingFeed(
        id feedID: UUID,
        using appState: AppState,
        selectsSavedFeed: Bool = true,
        initialFetchSnapshot: FeedInitialFetchSnapshot? = nil
    ) async -> FeedRefreshResult? {
        feedManagementPresentation.finishSavingFeed(
            id: feedID,
            using: appState,
            selectsSavedFeed: selectsSavedFeed
        )
        dependencies.feedSaveRefreshScheduler.schedule(
            id: feedID,
            initialFetchSnapshot: initialFetchSnapshot,
            using: appState,
            refresh: { id, snapshot in
                _ = await refreshFeed(id: id, initialFetchSnapshot: snapshot)
            }
        )
        return nil
    }

    @MainActor
    func waitForScheduledFeedSaveRefreshes() async {
        await dependencies.feedSaveRefreshScheduler.waitForAll()
    }

    @MainActor
    func completeFeedManagementFolderEditing(
        previousName: String?,
        updatedFolderName: String,
        using appState: AppState?
    ) {
        feedManagementPresentation.completeFeedManagementFolderEditing(
            previousName: previousName,
            updatedFolderName: updatedFolderName,
            using: appState
        )
    }

    @MainActor
    func completeFeedManagementFolderCreation(
        named folderName: String,
        using appState: AppState?
    ) {
        feedManagementPresentation.completeFeedManagementFolderCreation(named: folderName, using: appState)
    }

    @MainActor
    func completeFeedManagementMove(
        feedID: UUID,
        previousFolderName: String?,
        updatedFolderName: String?,
        using appState: AppState?
    ) {
        feedManagementPresentation.completeFeedManagementMove(
            feedID: feedID,
            previousFolderName: previousFolderName,
            updatedFolderName: updatedFolderName,
            using: appState
        )
    }

    @MainActor
    func completeFeedManagementFeedSave(
        id feedID: UUID,
        using appState: AppState?,
        selectsSavedFeed: Bool,
        initialFetchSnapshot: FeedInitialFetchSnapshot? = nil
    ) async -> FeedRefreshResult? {
        guard let appState else { return nil }
        return await finishSavingFeed(
            id: feedID,
            using: appState,
            selectsSavedFeed: selectsSavedFeed,
            initialFetchSnapshot: initialFetchSnapshot
        )
    }

    @MainActor
    func finishUnsubscribingFeed(id feedID: UUID, using appState: AppState) {
        feedManagementDestructiveActions.finishUnsubscribingFeed(id: feedID, using: appState)
    }

    @MainActor
    func requestFeedUnsubscribeConfirmation(
        id feedID: UUID,
        title feedTitle: String,
        using appState: AppState
    ) {
        feedManagementDestructiveActions.requestFeedUnsubscribeConfirmation(
            id: feedID,
            title: feedTitle,
            using: appState
        )
    }

    @MainActor
    func cancelFeedUnsubscribeConfirmation(using appState: AppState) {
        feedManagementDestructiveActions.cancelFeedUnsubscribeConfirmation(using: appState)
    }

    @MainActor
    func confirmPendingFeedUnsubscribe(using appState: AppState) {
        feedManagementDestructiveActions.confirmPendingFeedUnsubscribe(using: appState)
    }

    @MainActor
    func requestFolderDeleteConfirmation(
        named folderName: String,
        using appState: AppState
    ) {
        feedManagementDestructiveActions.requestFolderDeleteConfirmation(named: folderName, using: appState)
    }

    @MainActor
    func cancelFolderDeleteConfirmation(using appState: AppState) {
        feedManagementDestructiveActions.cancelFolderDeleteConfirmation(using: appState)
    }

    @MainActor
    func confirmPendingFolderDelete(using appState: AppState) {
        feedManagementDestructiveActions.confirmPendingFolderDelete(using: appState)
    }

    @MainActor
    func finishDeletingFolder(named folderName: String, using appState: AppState) {
        feedManagementDestructiveActions.finishDeletingFolder(named: folderName, using: appState)
    }

    @MainActor
    func unsubscribeFeed(id feedID: UUID, using appState: AppState) {
        feedManagementDestructiveActions.unsubscribeFeed(id: feedID, using: appState)
    }

    @MainActor
    func deleteFolder(named folderName: String, using appState: AppState) {
        feedManagementDestructiveActions.deleteFolder(named: folderName, using: appState)
    }

    @MainActor
    func dismissFeedManagement(using appState: AppState) {
        feedManagementPresentation.dismissFeedManagement(using: appState)
    }
}
