import Foundation
import UserNotifications

@MainActor
protocol UnreadAppIconBadgeServicing {
    func refreshBadgeCount() async
}

protocol AppIconBadgeApplying {
    func ensureBadgeAuthorization() async throws -> Bool
    func setBadgeCount(_ count: Int) async throws
}

@MainActor
final class UnreadAppIconBadgeService: UnreadAppIconBadgeServicing {
    private let logger: Logging
    private let feedRepository: any FeedRepository
    private let articleStateRepository: any ArticleStateRepository
    private let badgeApplier: any AppIconBadgeApplying

    init(
        logger: Logging,
        feedRepository: any FeedRepository,
        articleStateRepository: any ArticleStateRepository,
        badgeApplier: (any AppIconBadgeApplying)? = nil
    ) {
        self.logger = logger
        self.feedRepository = feedRepository
        self.articleStateRepository = articleStateRepository
        self.badgeApplier = badgeApplier ?? UserNotificationAppIconBadgeApplier()
    }

    func refreshBadgeCount() async {
        do {
            let unreadCount = try fetchUnreadArticleCount()
            guard try await badgeApplier.ensureBadgeAuthorization() else {
                logger.info("Skipped app icon badge update because badge authorization is unavailable")
                return
            }

            try await badgeApplier.setBadgeCount(unreadCount)
            logger.debug("Updated app icon badge count to \(unreadCount)")
        } catch {
            logger.error("Failed to update app icon badge count: \(error)")
        }
    }

    private func fetchUnreadArticleCount() throws -> Int {
        let feedIDs = try feedRepository.fetchActiveFeeds().map(\.id)
        guard feedIDs.isEmpty == false else { return 0 }

        let unreadCounts = try articleStateRepository.fetchUnreadCounts(feedIDs: feedIDs)
        return unreadCounts.values.reduce(0, +)
    }
}

final class UserNotificationAppIconBadgeApplier: AppIconBadgeApplying {
    private let notificationCenter: UNUserNotificationCenter

    init(notificationCenter: UNUserNotificationCenter = .current()) {
        self.notificationCenter = notificationCenter
    }

    func ensureBadgeAuthorization() async throws -> Bool {
        let settings = await notificationCenter.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return settings.badgeSetting == .enabled
        case .notDetermined:
            let granted = try await notificationCenter.requestAuthorization(options: [.badge])
            guard granted else { return false }
            let updatedSettings = await notificationCenter.notificationSettings()
            return updatedSettings.badgeSetting == .enabled
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    func setBadgeCount(_ count: Int) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            notificationCenter.setBadgeCount(count) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
