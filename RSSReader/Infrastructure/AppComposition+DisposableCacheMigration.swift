import Foundation

extension AppComposition {
    @MainActor
    static func runDisposableCacheMigrationIfNeeded(logger: Logging) {
        let migrationService = DisposableCacheMigrationService()
        runDisposableCacheMigrationIfNeeded(
            logger: logger,
            guard: disposableCacheMigrationGuard
        ) {
            try migrationService.removeLegacyFeedIconCacheDirectory()
        }
    }

    @MainActor
    static func runDisposableCacheMigrationIfNeeded(
        logger: Logging,
        guard bootstrapGuard: AppLaunchBootstrapGuard,
        cleanup: () throws -> Bool
    ) {
        let identifier = "DisposableCacheMigrationService.legacyFeedIconDirectory"
        guard bootstrapGuard.beginAttempt(identifier: identifier) else {
            logger.debug("Skipped disposable cache migration because app launch guard already attempted it")
            return
        }

        do {
            guard try cleanup() else { return }
            logger.info("Removed legacy RSSReaderSourceIcons cache directory")
        } catch {
            logger.error("Failed to remove legacy RSSReaderSourceIcons cache directory: \(error)")
        }
    }
}
