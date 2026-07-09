import Foundation

extension AppActionRouter {
    @MainActor
    func showInbox(using appState: AppState) {
        appState.selectSidebarSelection(.inbox)
    }

    @MainActor
    func showUnread(using appState: AppState) {
        appState.selectSidebarSelection(.unread)
    }

    @MainActor
    func showStarred(using appState: AppState) {
        appState.selectSidebarSelection(.starred)
    }

    @MainActor
    func showFeed(id feedID: UUID, using appState: AppState) {
        appState.selectSidebarSelection(.feed(feedID))
    }

    @MainActor
    func showFolder(named folderName: String, using appState: AppState) {
        appState.selectSidebarSelection(.folder(folderName))
    }

    @MainActor
    func selectArticle(id articleID: UUID?, using appState: AppState) {
        guard let articleID else {
            appState.selectedArticleID = nil
            return
        }

        guard shouldOpenSelectedArticleInSafariView() else {
            appState.selectedArticleID = articleID
            return
        }

        guard let articleQueryService else {
            logger.error("Article query service is unavailable for article opening mode policy")
            appState.selectedArticleID = articleID
            return
        }

        do {
            guard let article = try articleQueryService.fetchReaderArticle(id: articleID) else {
                logger.error("Skipped Safari View presentation because article \(articleID) was not found")
                appState.selectedArticleID = articleID
                return
            }

            guard openArticleDirectlyInSafari(article, using: appState) else {
                appState.selectedArticleID = articleID
                return
            }
        } catch {
            logger.error("Failed to apply article opening mode policy for article \(articleID): \(error)")
            appState.selectedArticleID = articleID
        }
    }

    @MainActor
    func applySidebarArticleFilter(_ filter: SidebarArticleFilter, using appState: AppState) {
        appState.selectSidebarArticleFilter(filter)
    }

    @MainActor
    @discardableResult
    func openArticleInSafari(_ article: ReaderArticleDTO, using appState: AppState) -> Bool {
        guard let url = URL(string: article.canonicalURL ?? article.articleURL) else {
            logger.error("Skipped opening article in Safari because URL is invalid for article \(article.id)")
            return false
        }

        guard appState.presentSafari(articleID: article.id, url: url) else {
            logger.error("Skipped opening article in Safari because URL is unsupported for article \(article.id)")
            return false
        }

        return true
    }

    @MainActor
    @discardableResult
    private func openArticleDirectlyInSafari(_ article: ReaderArticleDTO, using appState: AppState) -> Bool {
        guard let url = URL(string: article.canonicalURL ?? article.articleURL) else {
            logger.error("Skipped opening article directly in Safari because URL is invalid for article \(article.id)")
            return false
        }

        guard appState.presentSafariFromArticleList(articleID: article.id, url: url) else {
            logger.error("Skipped opening article directly in Safari because URL is unsupported for article \(article.id)")
            return false
        }

        return true
    }

    @MainActor
    func openArticleBodyLink(_ url: URL, articleID: UUID, using appState: AppState) {
        guard appState.presentSafari(articleID: articleID, url: url) else {
            logger.error("Skipped opening article body link in Safari because URL is unsupported for article \(articleID)")
            return
        }
    }

    @MainActor
    func closePresentedArticleSafari(using appState: AppState) {
        appState.dismissPresentedSafari()
    }

    @MainActor
    func showSettings(using appState: AppState) {
        appState.presentSettingsScreen()
    }

    @MainActor
    func dismissSettings(using appState: AppState) {
        appState.dismissSettingsScreen()
    }

    @MainActor
    private func shouldOpenSelectedArticleInSafariView() -> Bool {
        guard let appSettingsService else {
            return false
        }

        do {
            return try appSettingsService.fetchSettings().articleOpeningMode == .safariView
        } catch {
            logger.error("Failed to load app settings for article opening mode policy: \(error)")
            return false
        }
    }
}
