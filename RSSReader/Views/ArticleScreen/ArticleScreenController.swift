import Foundation
import Observation

typealias ArticleReadOnOpenHandler = @MainActor (UUID, ArticleUserStateSnapshot) -> Void

@MainActor
@Observable
final class ArticleScreenController {
    var screenState: ArticleScreenState

    init(previewScreenState: ArticleScreenState? = nil) {
        self.screenState = previewScreenState ?? ArticleScreenState()
    }

    func load(
        articleID: UUID?,
        dependencies: AppDependencies,
        preservesCurrentArticleDuringLoading: Bool = false,
        articleReadOnOpenHandler: ArticleReadOnOpenHandler? = nil
    ) async {
        screenState.beginLoading(
            articleID: articleID,
            preservesCurrentArticle: preservesCurrentArticleDuringLoading
        )

        guard let articleID else {
            return
        }

        guard let articleQueryService = dependencies.articleQueryService else {
            screenState.applyLoadingFailure(
                ReadingLocalization.articleQueryUnavailableMessage,
                articleID: articleID
            )
            return
        }

        do {
            if let article = try articleQueryService.fetchReaderArticle(id: articleID) {
                guard screenState.articleID == articleID else {
                    return
                }
                let resolvedArticle = applyMarkAsReadOnOpenPolicy(
                    to: article,
                    dependencies: dependencies,
                    articleReadOnOpenHandler: articleReadOnOpenHandler
                )
                guard screenState.articleID == articleID else {
                    return
                }
                screenState.applyLoadedArticle(resolvedArticle)
            } else {
                guard screenState.articleID == articleID else {
                    return
                }
                screenState.applyArticleNotFound(articleID: articleID)
            }
        } catch {
            guard screenState.articleID == articleID else {
                return
            }
            dependencies.logger.error("Failed to load article by ID \(articleID): \(error)")
            screenState.applyLoadingFailure(
                error.localizedDescription,
                articleID: articleID
            )
        }
    }

    func toggleArticleReadStatus(
        dependencies: AppDependencies,
        isPreviewMode: Bool
    ) {
        guard let article = screenState.article else { return }
        let requestedIsRead = article.isRead == false
        let resolvedIsRead: Bool

        if isPreviewMode == false {
            guard let articleStateService = dependencies.articleStateService else {
                dependencies.logger.error("Article state service is unavailable for read toggle action")
                return
            }

            do {
                let persistedState: ArticleUserStateSnapshot
                if requestedIsRead {
                    persistedState = try articleStateService.markAsRead(
                        feedID: article.feedID,
                        articleExternalID: article.articleExternalID,
                        at: .now
                    )
                } else {
                    persistedState = try articleStateService.markAsUnread(
                        feedID: article.feedID,
                        articleExternalID: article.articleExternalID,
                        at: .now
                    )
                }
                resolvedIsRead = persistedState.isRead
            } catch {
                dependencies.logger.error("Failed to toggle article read status: \(error)")
                return
            }
        } else {
            resolvedIsRead = requestedIsRead
        }

        screenState.applyArticleMutation(article.updating(isRead: resolvedIsRead))
    }

    func toggleArticleStarredStatus(
        dependencies: AppDependencies,
        isPreviewMode: Bool
    ) {
        guard let article = screenState.article else { return }
        let requestedIsStarred = article.isStarred == false
        let resolvedIsStarred: Bool

        if isPreviewMode == false {
            guard let articleStateService = dependencies.articleStateService else {
                dependencies.logger.error("Article state service is unavailable for starred toggle action")
                return
            }

            do {
                let persistedState = try articleStateService.toggleStarred(
                    feedID: article.feedID,
                    articleExternalID: article.articleExternalID,
                    at: .now
                )
                resolvedIsStarred = persistedState.isStarred
            } catch {
                dependencies.logger.error("Failed to toggle article starred status: \(error)")
                return
            }
        } else {
            resolvedIsStarred = requestedIsStarred
        }

        screenState.applyArticleMutation(article.updating(isStarred: resolvedIsStarred))
    }

    func openSourceArticle(
        dependencies: AppDependencies,
        appState: AppState,
        openExternalURL: (URL) -> Void
    ) {
        guard let request = sourceArticleOpeningRequest(dependencies: dependencies) else { return }
        switch request {
        case .inAppBrowser(_):
            guard let article = screenState.article else { return }
            dependencies.appActions.openArticleInSafari(article, using: appState)
        case .externalBrowser(let url):
            openExternalURL(url)
        }
    }

    func sourceArticleOpeningRequest(
        dependencies: AppDependencies
    ) -> ArticleSourceOpeningRequest? {
        guard let article = screenState.article else { return nil }
        guard let url = ArticleScreenShareURLResolver.resolveShareURL(article: article) else {
            return nil
        }

        switch articleSourceLinkOpeningPolicy(dependencies: dependencies) {
        case .inAppBrowser:
            guard ArticleSafariRoute.canOpen(url) else { return nil }
            return .inAppBrowser(ArticleSafariRoute(articleID: article.id, url: url))
        case .externalBrowser:
            return .externalBrowser(url)
        }
    }

    func handleBodyLinkTap(
        _ url: URL,
        dependencies: AppDependencies,
        appState: AppState,
        openExternalURL: (URL) -> Void
    ) {
        guard let article = screenState.article else { return }

        switch articleBodyLinkOpeningPolicy(dependencies: dependencies) {
        case .inAppBrowser:
            dependencies.appActions.openArticleBodyLink(url, articleID: article.id, using: appState)
        case .externalBrowser:
            openExternalURL(url)
        }
    }

    private func applyMarkAsReadOnOpenPolicy(
        to article: ReaderArticleDTO,
        dependencies: AppDependencies,
        articleReadOnOpenHandler: ArticleReadOnOpenHandler?
    ) -> ReaderArticleDTO {
        guard article.isRead == false else {
            return article
        }

        guard shouldMarkAsReadOnOpen(dependencies: dependencies) else {
            return article
        }

        guard let articleStateService = dependencies.articleStateService else {
            dependencies.logger.error("Article state service is unavailable for mark-as-read-on-open policy")
            return article
        }

        do {
            let persistedState = try articleStateService.markAsRead(
                feedID: article.feedID,
                articleExternalID: article.articleExternalID,
                at: .now
            )
            articleReadOnOpenHandler?(article.id, persistedState)
            return article.updating(isRead: persistedState.isRead)
        } catch {
            dependencies.logger.error("Failed to apply mark-as-read-on-open policy: \(error)")
            return article
        }
    }

    private func shouldMarkAsReadOnOpen(dependencies: AppDependencies) -> Bool {
        guard let appSettingsService = dependencies.appSettingsService else {
            return true
        }

        do {
            return try appSettingsService.fetchSettings().markAsReadOnOpen
        } catch {
            dependencies.logger.error("Failed to load app settings for mark-as-read-on-open policy: \(error)")
            return true
        }
    }

    private func articleBodyLinkOpeningPolicy(
        dependencies: AppDependencies
    ) -> ArticleBodyLinkOpeningPolicy {
        guard let appSettingsService = dependencies.appSettingsService else {
            return .inAppBrowser
        }

        do {
            return try appSettingsService.fetchSettings().articleBodyLinkOpeningPolicy
        } catch {
            dependencies.logger.error("Failed to load app settings for article body link opening policy: \(error)")
            return .inAppBrowser
        }
    }

    private func articleSourceLinkOpeningPolicy(
        dependencies: AppDependencies
    ) -> ArticleSourceLinkOpeningPolicy {
        guard let appSettingsService = dependencies.appSettingsService else {
            return .inAppBrowser
        }

        do {
            return try appSettingsService.fetchSettings().articleSourceLinkOpeningPolicy
        } catch {
            dependencies.logger.error("Failed to load app settings for article source link opening policy: \(error)")
            return .inAppBrowser
        }
    }
}

enum ArticleSourceOpeningRequest: Equatable {
    case inAppBrowser(ArticleSafariRoute)
    case externalBrowser(URL)
}
