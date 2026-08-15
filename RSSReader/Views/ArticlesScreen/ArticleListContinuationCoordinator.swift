import Foundation

@MainActor
enum ArticleListContinuationCoordinator {
    static func canLoadNextArticle(
        appState: AppState,
        controller: ArticlesScreenController
    ) -> Bool {
        guard let sessionReference = appState.currentArticleListSessionReference else {
            return false
        }

        return controller.hasNextPageContinuation(for: sessionReference.id)
    }

    static func loadAdjacentArticle(
        _ direction: ReaderAdjacentArticleNavigationDirection,
        appState: AppState,
        controller: ArticlesScreenController,
        dependencies: AppDependencies
    ) async -> UUID? {
        guard direction == .next,
              let sourceArticleID = appState.selectedArticleID,
              appState.adjacentArticleID(direction) == nil,
              let sessionReference = appState.currentArticleListSessionReference,
              controller.hasNextPageContinuation(for: sessionReference.id) else {
            return nil
        }

        let continuationSnapshot = await controller.loadNextPage(
            dependencies: dependencies
        )
        guard let continuationSnapshot,
              continuationSnapshot.sessionID == sessionReference.id,
              appState.currentArticleListSessionReference == sessionReference else {
            return nil
        }

        appState.updateArticleNavigationContext(
            continuationSnapshot.visibleArticleIDs,
            sidebarSelection: sessionReference.sidebarSelection,
            sidebarArticleFilter: sessionReference.sidebarArticleFilter,
            articleListSessionID: sessionReference.id
        )
        guard appState.selectedArticleID == sourceArticleID else {
            return nil
        }
        return appState.adjacentArticleID(direction)
    }
}
