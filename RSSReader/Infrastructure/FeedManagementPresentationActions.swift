import Foundation

/// App-level orchestration; persistence and business rules remain in the injected services.
@MainActor
struct FeedManagementPresentationActions {
    private let logger: Logging
    private let folderRepository: (any FolderRepository)?
    private let feedManagementService: (any FeedManagementService)?

    init(
        logger: Logging,
        folderRepository: (any FolderRepository)?,
        feedManagementService: (any FeedManagementService)?
    ) {
        self.logger = logger
        self.folderRepository = folderRepository
        self.feedManagementService = feedManagementService
    }

    func showFeedManagement(using appState: AppState) {
        appState.presentFeedManagementScreen()
    }

    func showFeedEditor(id feedID: UUID, using appState: AppState) {
        appState.presentFeedManagementScreen(launchContext: .editFeed(feedID))
    }

    func showFeedOrganizer(id feedID: UUID, using appState: AppState) {
        appState.presentFeedManagementScreen(launchContext: .organizeFeed(feedID))
    }

    func showFolderEditor(named folderName: String, using appState: AppState) {
        guard let folderRepository else {
            logger.error("Folder repository is unavailable for folder editing")
            return
        }

        do {
            guard let folder = try folderRepository.fetchFolder(name: folderName) else {
                logger.error("Skipped folder editor presentation because folder \(folderName) was not found")
                return
            }
            appState.presentFeedManagementScreen(launchContext: .editFolder(folder.id))
        } catch {
            logger.error("Failed to resolve folder editor presentation for \(folderName): \(error)")
        }
    }

    func loadFeedManagementAddFeedContext(
        into screenState: inout FeedManagementScreenState
    ) {
        guard let feedManagementService else {
            logger.error("Skipped add-feed folder context loading because feed management service is unavailable")
            screenState.applyAddFeedFolderContext(folders: [])
            return
        }

        do {
            let folders = try feedManagementService.fetchFolders()
            screenState.applyAddFeedFolderContext(folders: folders)
        } catch {
            logger.error("Failed to load folder context for add-feed flow: \(error)")
            screenState.applyAddFeedFolderContext(folders: [])
        }
    }

    func loadFeedManagementAddFeedEditContext(
        feedID: UUID,
        into screenState: inout FeedManagementScreenState
    ) {
        screenState.resetAddFeedForEntry()

        guard let feedManagementService else {
            logger.error("Skipped feed editor context loading because feed management service is unavailable")
            screenState.applyAddFeedFolderContext(folders: [])
            return
        }

        do {
            guard let feed = try feedManagementService.fetchFeed(id: feedID) else {
                logger.error("Skipped feed editor context loading because feed \(feedID) was not found")
                screenState.applyAddFeedFolderContext(folders: [])
                return
            }

            let folders = try feedManagementService.fetchFolders()
            screenState.applyAddFeedEditContext(feed: feed, folders: folders)
        } catch {
            logger.error("Failed to load feed editor context for feed management screen: \(error)")
            screenState.applyAddFeedFolderContext(folders: [])
        }
    }

    func loadFeedManagementCreateFolderContext(
        into screenState: inout FeedManagementScreenState
    ) {
        guard let feedManagementService else {
            logger.error("Skipped create-folder context loading because feed management service is unavailable")
            screenState.applyCreateFolderServiceUnavailable(
                title: FeedManagementLocalization.folderCreationUnavailableTitle,
                message: FeedManagementLocalization.folderCreationUnavailableMessage
            )
            return
        }

        do {
            let folders = try feedManagementService.fetchFolders()
            screenState.applyCreateFolderContext(folders: folders)
        } catch {
            logger.error("Failed to load folder context for feed management screen: \(error)")
            screenState.applyCreateFolderFailure(
                FeedManagementLocalization.existingFoldersLoadFailureMessage
            )
        }
    }

    func loadFeedManagementCreateFolderEditContext(
        folderID: UUID,
        into screenState: inout FeedManagementScreenState
    ) {
        screenState.resetCreateFolderForEntry()

        guard let feedManagementService else {
            logger.error("Skipped folder editor context loading because feed management service is unavailable")
            screenState.applyCreateFolderServiceUnavailable(
                title: FeedManagementLocalization.folderEditingUnavailableTitle,
                message: FeedManagementLocalization.folderEditingUnavailableMessage
            )
            return
        }

        do {
            guard let folder = try feedManagementService.fetchFolder(id: folderID) else {
                logger.error("Skipped folder editor context loading because folder \(folderID) was not found")
                return
            }

            let folders = try feedManagementService.fetchFolders()
            screenState.applyCreateFolderEditContext(folder: folder, folders: folders)
        } catch {
            logger.error("Failed to load folder editor context for feed management screen: \(error)")
            screenState.applyCreateFolderFailure(
                FeedManagementLocalization.folderDetailsLoadFailureMessage
            )
        }
    }

    func loadFeedManagementMoveFeedContext(
        selectedFeedID: UUID? = nil,
        into screenState: inout FeedManagementScreenState
    ) {
        guard let feedManagementService else {
            logger.error("Skipped move-feed context loading because feed management service is unavailable")
            screenState.applyMoveFeedContext(feeds: [], folders: [])
            screenState.applyMoveFeedFailure(
                FeedManagementLocalization.feedMovesEnvironmentUnavailableMessage
            )
            return
        }

        do {
            let feeds = try feedManagementService.fetchFeeds()
            let folders = try feedManagementService.fetchFolders()
            screenState.applyMoveFeedContext(
                feeds: feeds,
                folders: folders,
                selectedFeedID: selectedFeedID
            )
        } catch {
            logger.error("Failed to load move-feed context for feed management screen: \(error)")
            screenState.applyMoveFeedContext(feeds: [], folders: [])
            screenState.applyMoveFeedFailure(
                FeedManagementLocalization.existingFeedsLoadFailureMessage
            )
        }
    }

    func restoreAddFeedAfterCreatingFolder(
        _ folder: FeedManagementFolderSummary,
        into screenState: inout FeedManagementScreenState
    ) {
        loadFeedManagementAddFeedContext(into: &screenState)
        screenState.selectAddFeedFolderPlacement(.folder(folder.id))
        screenState.presentScenario(.addFeed)
    }

    func finishFolderEditing(
        previousName: String,
        updatedFolderName: String,
        using appState: AppState
    ) {
        appState.requestSidebarReload()
        if appState.selectedSidebarSelection == .folder(previousName) {
            appState.reconcileSidebarSelection(
                .folder(updatedFolderName),
                expectedSelection: .folder(previousName),
                expectedFilter: appState.selectedSidebarArticleFilter
            )
        }
        dismissFeedManagement(using: appState)
    }

    func finishCreatingFolder(named folderName: String, using appState: AppState) {
        logger.info("Finished feed management folder creation for \(folderName)")
        appState.requestSidebarReload()
    }

    func finishMovingFeed(
        feedID: UUID,
        previousFolderName: String?,
        updatedFolderName: String?,
        using appState: AppState
    ) {
        appState.requestSidebarReload()

        switch appState.selectedSidebarSelection {
        case .feed(let selectedFeedID):
            if selectedFeedID == feedID {
                appState.requestArticleListReload()
            }
        case .folder(let folderName):
            if folderName == previousFolderName || folderName == updatedFolderName {
                appState.requestArticleListReload()
            }
        case .inbox, .unread, .starred, .none:
            break
        }

        dismissFeedManagement(using: appState)
    }

    func completeFeedManagementFolderEditing(
        previousName: String?,
        updatedFolderName: String,
        using appState: AppState?
    ) {
        guard let appState, let previousName else { return }
        finishFolderEditing(
            previousName: previousName,
            updatedFolderName: updatedFolderName,
            using: appState
        )
    }

    func completeFeedManagementFolderCreation(
        named folderName: String,
        using appState: AppState?
    ) {
        guard let appState else { return }
        finishCreatingFolder(named: folderName, using: appState)
    }

    func completeFeedManagementMove(
        feedID: UUID,
        previousFolderName: String?,
        updatedFolderName: String?,
        using appState: AppState?
    ) {
        guard let appState else { return }
        finishMovingFeed(
            feedID: feedID,
            previousFolderName: previousFolderName,
            updatedFolderName: updatedFolderName,
            using: appState
        )
    }

    func dismissFeedManagement(using appState: AppState) {
        appState.dismissFeedManagementScreen()
    }

    func finishSavingFeed(id feedID: UUID, using appState: AppState, selectsSavedFeed: Bool) {
        appState.requestSidebarReload()
        appState.selectSidebarSelection(selectsSavedFeed ? .feed(feedID) : nil)
        dismissFeedManagement(using: appState)
    }
}
