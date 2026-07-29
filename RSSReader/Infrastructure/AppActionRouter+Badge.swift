import Foundation

struct RemoteSyncImportAppAction {
    private let logger: Logging
    private let unreadAppIconBadgeService: (any UnreadAppIconBadgeServicing)?

    init(
        logger: Logging,
        unreadAppIconBadgeService: (any UnreadAppIconBadgeServicing)?
    ) {
        self.logger = logger
        self.unreadAppIconBadgeService = unreadAppIconBadgeService
    }

    @MainActor
    func perform(using appState: AppState) {
        appState.requestRemoteSyncImportReload()

        guard let unreadAppIconBadgeService else {
            logger.debug("Unread app icon badge service is unavailable after remote sync import")
            return
        }

        Task { @MainActor in
            await unreadAppIconBadgeService.refreshBadgeCount()
        }
    }
}

extension AppActionRouter {
    @MainActor
    func refreshUnreadAppIconBadgeCount() async {
        guard let unreadAppIconBadgeService else {
            logger.debug("Unread app icon badge service is unavailable")
            return
        }

        await unreadAppIconBadgeService.refreshBadgeCount()
    }

    @MainActor
    func applyUnreadAppIconBadgePreference(isEnabled: Bool) {
        guard let unreadAppIconBadgeService else {
            logger.debug("Unread app icon badge service is unavailable")
            return
        }

        Task { @MainActor in
            await unreadAppIconBadgeService.applyBadgePreference(isEnabled: isEnabled)
        }
    }

    @MainActor
    func scheduleUnreadAppIconBadgeRefresh() {
        Task { @MainActor in
            await refreshUnreadAppIconBadgeCount()
        }
    }
}
