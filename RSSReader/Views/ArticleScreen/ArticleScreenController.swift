import Foundation
import Observation

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
        articleReadOnOpenHandler: ((UUID) -> Void)? = nil
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
        let newIsRead = article.isRead == false

        if isPreviewMode == false {
            guard let articleStateService = dependencies.articleStateService else {
                dependencies.logger.error("Article state service is unavailable for read toggle action")
                return
            }

            do {
                if newIsRead {
                    _ = try articleStateService.markAsRead(
                        feedID: article.feedID,
                        articleExternalID: article.articleExternalID,
                        at: .now
                    )
                } else {
                    _ = try articleStateService.markAsUnread(
                        feedID: article.feedID,
                        articleExternalID: article.articleExternalID,
                        at: .now
                    )
                }
            } catch {
                dependencies.logger.error("Failed to toggle article read status: \(error)")
                return
            }
        }

        screenState.applyArticleMutation(article.updating(isRead: newIsRead))
    }

    func toggleArticleStarredStatus(
        dependencies: AppDependencies,
        isPreviewMode: Bool
    ) {
        guard let article = screenState.article else { return }
        let newIsStarred = article.isStarred == false

        if isPreviewMode == false {
            guard let articleStateService = dependencies.articleStateService else {
                dependencies.logger.error("Article state service is unavailable for starred toggle action")
                return
            }

            do {
                _ = try articleStateService.toggleStarred(
                    feedID: article.feedID,
                    articleExternalID: article.articleExternalID,
                    at: .now
                )
            } catch {
                dependencies.logger.error("Failed to toggle article starred status: \(error)")
                return
            }
        }

        screenState.applyArticleMutation(article.updating(isStarred: newIsStarred))
    }

    func openSourceArticle(
        dependencies: AppDependencies,
        appState: AppState,
        openExternalURL: (URL) -> Void
    ) {
        guard let article = screenState.article else { return }
        switch articleSourceLinkOpeningPolicy(dependencies: dependencies) {
        case .inAppBrowser:
            dependencies.appActions.openArticleInSafari(article, using: appState)
        case .externalBrowser:
            guard let url = ArticleScreenShareURLResolver.resolveShareURL(article: article) else {
                return
            }
            openExternalURL(url)
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
        articleReadOnOpenHandler: ((UUID) -> Void)?
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
            _ = try articleStateService.markAsRead(
                feedID: article.feedID,
                articleExternalID: article.articleExternalID,
                at: .now
            )
            articleReadOnOpenHandler?(article.id)
            return article.updating(isRead: true)
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
