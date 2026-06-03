import Foundation

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
