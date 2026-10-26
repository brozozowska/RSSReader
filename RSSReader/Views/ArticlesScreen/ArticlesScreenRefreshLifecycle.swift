import Foundation

/// Owns manual-refresh generations and the failed-only retry plan, never screen state.
@MainActor
final class ArticlesScreenRefreshLifecycle {
    struct Identity {
        let generation: Int
        let sessionID: UUID
        let context: ArticleListSession.Context
    }

    private var generation = 0
    private var retryFeedIDs: [UUID] = []

    func reset() {
        generation += 1
        retryFeedIDs = []
    }

    func begin(sessionID: UUID, context: ArticleListSession.Context) -> Identity {
        generation += 1
        return Identity(generation: generation, sessionID: sessionID, context: context)
    }

    func isCurrent(_ identity: Identity, sessionID: UUID, context: ArticleListSession.Context) -> Bool {
        identity.generation == generation && identity.sessionID == sessionID && identity.context == context
    }

    func refresh(
        context: ManualFeedRefreshContext,
        dependencies: AppDependencies,
        appState: AppState,
        requestsArticleListReload: Bool
    ) async -> FeedRefreshBatchResult? {
        if retryFeedIDs.isEmpty == false {
            return await dependencies.appActions.retryFeeds(
                retryFeedIDs,
                context: context,
                using: appState,
                requestsArticleListReload: requestsArticleListReload
            )
        }
        return await dependencies.appActions.refreshSelection(
            context,
            using: appState,
            requestsArticleListReload: requestsArticleListReload
        )
    }

    func accept(_ result: FeedRefreshBatchResult?) {
        retryFeedIDs = result?.retryFeedIDs ?? retryFeedIDs
    }

    func failureMessage(for result: FeedRefreshBatchResult) -> String? {
        guard result.hasUnsuccessfulOutcome else {
            return nil
        }

        let unsuccessfulCount = max(
            result.retryFeedIDs.count,
            result.batchErrorDescription == nil ? 0 : 1
        )

        if let firstError = result.failureDescriptions.first {
            if unsuccessfulCount == 1 {
                return firstError
            }
            return ReadingLocalization.multipleFeedsRefreshFailed(
                count: unsuccessfulCount,
                firstError: firstError
            )
        }

        if unsuccessfulCount == 1 {
            return ReadingLocalization.singleFeedRefreshFailed
        }

        return ReadingLocalization.multipleFeedsRefreshFailed(count: unsuccessfulCount)
    }
}
