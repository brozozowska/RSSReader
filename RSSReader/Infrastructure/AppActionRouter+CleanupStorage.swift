import Foundation

extension AppActionRouter {
    @MainActor
    @discardableResult
    func cleanupArticles(
        policy: ArticleRetentionPolicy,
        now: Date = .now
    ) -> ArticleRetentionCleanupResult? {
        guard let articleRetentionCleanupService else {
            logger.debug("Article retention cleanup service is unavailable")
            return nil
        }

        do {
            let result = try articleRetentionCleanupService.cleanupArticles(policy: policy, now: now)
            cleanupFeedFetchLogs(now: now)
            return result
        } catch {
            logger.error("Failed to apply article retention cleanup: \(error)")
            return nil
        }
    }

    @MainActor
    @discardableResult
    func cleanupArticlesUsingCurrentSettings(now: Date = .now) -> ArticleRetentionCleanupResult? {
        guard let appSettingsService else {
            logger.debug("App settings service is unavailable for article retention cleanup")
            return nil
        }

        do {
            let settings = try appSettingsService.fetchSettings()
            return cleanupArticles(policy: settings.articleRetentionPolicy, now: now)
        } catch {
            logger.error("Failed to load article retention settings for cleanup: \(error)")
            return nil
        }
    }

    @MainActor
    @discardableResult
    func purgeArchivedArticles() -> ArticleArchivePurgeResult? {
        guard let articleRetentionCleanupService else {
            logger.debug("Article retention cleanup service is unavailable for article archive purge")
            return nil
        }

        do {
            let result = try articleRetentionCleanupService.purgeArchivedArticles()
            cleanupFeedFetchLogs()
            return result
        } catch {
            logger.error("Failed to purge archived articles: \(error)")
            return nil
        }
    }

    @MainActor
    @discardableResult
    func cleanupFeedFetchLogs(now: Date = .now) -> FeedFetchLogCleanupResult? {
        guard let persistenceBoundedGrowthCleanupService else {
            logger.debug("Persistence bounded growth cleanup service is unavailable")
            return nil
        }

        do {
            return try persistenceBoundedGrowthCleanupService.cleanupFeedFetchLogs(now: now)
        } catch {
            logger.error("Failed to clean up feed fetch logs: \(error)")
            return nil
        }
    }

    @MainActor
    @discardableResult
    func cleanupPersistenceBoundedGrowth(now: Date = .now) -> PersistenceBoundedGrowthCleanupResult? {
        guard let persistenceBoundedGrowthCleanupService else {
            logger.debug("Persistence bounded growth cleanup service is unavailable")
            return nil
        }

        do {
            return try persistenceBoundedGrowthCleanupService.cleanupBoundedGrowth(now: now)
        } catch {
            logger.error("Failed to clean up bounded persistence growth: \(error)")
            return nil
        }
    }
}
