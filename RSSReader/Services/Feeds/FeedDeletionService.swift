import Foundation
import SwiftData

enum FeedDeletionService {
    static func delete(
        _ feed: Feed,
        in modelContext: ModelContext,
        persistenceOperationRecorder: SwiftDataRepositoryOperationRecorder = { _ in }
    ) throws {
        let feedID = feed.id

        try modelContext.delete(
            model: Article.self,
            where: #Predicate<Article> { article in
                article.feedID == feedID
            }
        )

        try modelContext.delete(
            model: ArticleState.self,
            where: #Predicate<ArticleState> { articleState in
                articleState.feedID == feedID
            }
        )

        try modelContext.delete(
            model: FeedFetchLog.self,
            where: #Predicate<FeedFetchLog> { feedFetchLog in
                feedFetchLog.feedID == feedID
            }
        )

        modelContext.delete(feed)

        if modelContext.hasChanges {
            persistenceOperationRecorder(.save)
            try modelContext.save()
        }
    }
}
