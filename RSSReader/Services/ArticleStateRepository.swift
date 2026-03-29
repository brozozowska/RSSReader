import Foundation
import SwiftData

struct ArticleUserStateSnapshot: Sendable {
    let articleExternalID: String
    let feedID: UUID
    let isRead: Bool
    let readAt: Date?
    let isStarred: Bool
    let starredAt: Date?
    let isHidden: Bool
    let hiddenAt: Date?
    let lastInteractionAt: Date?
    let updatedAt: Date

    init(articleState: ArticleState) {
        self.articleExternalID = articleState.articleExternalID
        self.feedID = articleState.feedID
        self.isRead = articleState.isRead
        self.readAt = articleState.readAt
        self.isStarred = articleState.isStarred
        self.starredAt = articleState.starredAt
        self.isHidden = articleState.isHidden
        self.hiddenAt = articleState.hiddenAt
        self.lastInteractionAt = articleState.lastInteractionAt
        self.updatedAt = articleState.updatedAt
    }
}

@MainActor
protocol ArticleStateRepository {
    func fetchState(feedID: UUID, articleExternalID: String) throws -> ArticleState?
    func fetchStateSnapshot(feedID: UUID, articleExternalID: String) throws -> ArticleUserStateSnapshot?
    func fetchStateSnapshots(feedID: UUID, articleExternalIDs: [String]) throws -> [String: ArticleUserStateSnapshot]
    func fetchStateSnapshots(for articles: [Article]) throws -> [String: ArticleUserStateSnapshot]
    func fetchUnreadCounts(feedIDs: [UUID]) throws -> [UUID: Int]
}

@MainActor
final class SwiftDataArticleStateRepository: ArticleStateRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchState(feedID: UUID, articleExternalID: String) throws -> ArticleState? {
        var descriptor = FetchDescriptor<ArticleState>(
            predicate: #Predicate<ArticleState> { articleState in
                articleState.feedID == feedID && articleState.articleExternalID == articleExternalID
            }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func fetchStateSnapshot(feedID: UUID, articleExternalID: String) throws -> ArticleUserStateSnapshot? {
        try fetchState(feedID: feedID, articleExternalID: articleExternalID)
            .map(ArticleUserStateSnapshot.init(articleState:))
    }

    func fetchStateSnapshots(feedID: UUID, articleExternalIDs: [String]) throws -> [String: ArticleUserStateSnapshot] {
        let normalizedIDs = Array(
            Set(
                articleExternalIDs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { $0.isEmpty == false }
            )
        )

        guard normalizedIDs.isEmpty == false else { return [:] }

        let descriptor = FetchDescriptor<ArticleState>(
            predicate: #Predicate<ArticleState> { articleState in
                articleState.feedID == feedID
            }
        )

        let states = try modelContext.fetch(descriptor)
        return states.reduce(into: [String: ArticleUserStateSnapshot]()) { partialResult, state in
            guard normalizedIDs.contains(state.articleExternalID) else { return }
            partialResult[state.articleExternalID] = ArticleUserStateSnapshot(articleState: state)
        }
    }

    func fetchStateSnapshots(for articles: [Article]) throws -> [String: ArticleUserStateSnapshot] {
        let groupedArticleIDs = Dictionary(grouping: articles, by: \.feedID)
        var snapshotsByCompositeKey: [String: ArticleUserStateSnapshot] = [:]

        for (feedID, groupedArticles) in groupedArticleIDs {
            let articleExternalIDs = groupedArticles.map(\.externalID)
            let snapshots = try fetchStateSnapshots(feedID: feedID, articleExternalIDs: articleExternalIDs)

            for (externalID, snapshot) in snapshots {
                snapshotsByCompositeKey[compositeKey(feedID: feedID, articleExternalID: externalID)] = snapshot
            }
        }

        return snapshotsByCompositeKey
    }

    func fetchUnreadCounts(feedIDs: [UUID]) throws -> [UUID: Int] {
        let normalizedFeedIDs = Set(feedIDs)
        guard normalizedFeedIDs.isEmpty == false else { return [:] }

        let articleDescriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { article in
                article.isDeletedAtSource == false
            }
        )
        let articles = try modelContext.fetch(articleDescriptor)

        let relevantArticles = articles.filter { normalizedFeedIDs.contains($0.feedID) }
        guard relevantArticles.isEmpty == false else {
            return Dictionary(uniqueKeysWithValues: normalizedFeedIDs.map { ($0, 0) })
        }

        let stateSnapshots = try fetchStateSnapshots(for: relevantArticles)
        var unreadCounts = Dictionary(uniqueKeysWithValues: normalizedFeedIDs.map { ($0, 0) })

        for article in relevantArticles {
            let key = compositeKey(feedID: article.feedID, articleExternalID: article.externalID)
            let state = stateSnapshots[key]
            let isHidden = state?.isHidden ?? false
            let isRead = state?.isRead ?? false

            guard isHidden == false, isRead == false else { continue }
            unreadCounts[article.feedID, default: 0] += 1
        }

        return unreadCounts
    }

    private func compositeKey(feedID: UUID, articleExternalID: String) -> String {
        "\(feedID.uuidString)|\(articleExternalID)"
    }
}
