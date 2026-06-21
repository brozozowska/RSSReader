import Foundation

@MainActor
extension SettingsScreenController {
    func clearArticleImageCache(dependencies: AppDependencies) async {
        ArticleImageMemoryCache.shared.removeAllImages()
        URLCache.shared.removeAllCachedResponses()

        do {
            try await ArticleImageDiskCache.shared.removeAll()
            screenState.applyArticleImageCacheAvailability(false)
            dependencies.logger.info("Cleared article image cache")
        } catch {
            dependencies.logger.error("Failed to clear article image disk cache: \(error)")
            await refreshArticleImageCacheAvailability(dependencies: dependencies)
        }
    }

    func clearFeedIconCache(
        dependencies: AppDependencies,
        appState: AppState?
    ) async {
        do {
            try await dependencies.feedIconCache.removeAllCachedData()
            screenState.applyFeedIconCacheAvailability(false)
            appState?.requestFeedIconCacheReset()
            dependencies.logger.info("Cleared feed icon cache")
        } catch {
            dependencies.logger.error("Failed to clear feed icon cache: \(error)")
            await refreshFeedIconCacheAvailability(dependencies: dependencies)
        }
    }

    func purgeArchivedArticles(
        dependencies: AppDependencies,
        appState: AppState?
    ) {
        guard let result = dependencies.appActions.purgeArchivedArticles() else {
            refreshArchivedArticlesAvailability(dependencies: dependencies)
            return
        }

        screenState.applyArchivedArticlesAvailability(false)
        if result.deletedCount > 0 {
            appState?.requestSidebarReload()
            appState?.requestArticleListReload()
        }
    }
}
