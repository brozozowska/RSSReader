import Foundation
import SwiftData

enum FeedDeletionService {
    static func delete(_ feed: Feed, in modelContext: ModelContext) throws {
        let feedID = feed.id

        try modelContext.delete(
            model: ArticleState.self,
            where: #Predicate<ArticleState> { articleState in
                articleState.feedID == feedID
            }
        )

        modelContext.delete(feed)

        if modelContext.hasChanges {
            try modelContext.save()
        }
    }
}
