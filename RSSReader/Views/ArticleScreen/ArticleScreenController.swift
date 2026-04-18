import Foundation
import Observation

@MainActor
@Observable
final class ArticleScreenController {
    var screenState: ArticleScreenState

    init(previewScreenState: ArticleScreenState? = nil) {
        self.screenState = previewScreenState ?? ArticleScreenState()
    }

    func load(articleID: UUID?, dependencies: AppDependencies) async {
        screenState.beginLoading(articleID: articleID)

        guard let articleID else {
            return
        }

        guard let articleQueryService = dependencies.articleQueryService else {
            screenState.applyLoadingFailure(
                "Article query service is unavailable.",
                articleID: articleID
            )
            return
        }

        do {
            if let article = try articleQueryService.fetchReaderArticle(id: articleID) {
                let resolvedArticle = applyMarkAsReadOnOpenPolicy(
                    to: article,
                    dependencies: dependencies
                )
                screenState.applyLoadedArticle(resolvedArticle)
            } else {
                screenState.applyArticleNotFound(articleID: articleID)
            }
        } catch {
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

    func openArticleInAppBrowser(
        dependencies: AppDependencies,
        appState: AppState
    ) {
        guard let article = screenState.article else { return }
        dependencies.openArticleInWebView(article, using: appState)
    }

    private func applyMarkAsReadOnOpenPolicy(
        to article: ReaderArticleDTO,
        dependencies: AppDependencies
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
}
