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
                screenState.applyLoadedArticle(article)
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

    func presentShareSheet() {
        screenState.presentShareSheet()
    }

    func dismissShareSheet() {
        screenState.dismissShareSheet()
    }
}
