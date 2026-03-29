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

struct ArticleStateUpsert: Sendable {
    var isRead: Bool? = nil
    var readAt: Date? = nil
    var isStarred: Bool? = nil
    var starredAt: Date? = nil
    var isHidden: Bool? = nil
    var hiddenAt: Date? = nil
    var lastInteractionAt: Date? = nil
    var updatedAt: Date = .now
}

@MainActor
protocol ArticleStateRepository {
    func fetchState(feedID: UUID, articleExternalID: String) throws -> ArticleState?
    func fetchOrCreate(feedID: UUID, articleExternalID: String) throws -> ArticleState
    func fetchStateSnapshot(feedID: UUID, articleExternalID: String) throws -> ArticleUserStateSnapshot?
    func fetchStateSnapshots(feedID: UUID, articleExternalIDs: [String]) throws -> [String: ArticleUserStateSnapshot]
    func fetchStateSnapshots(for articles: [Article]) throws -> [String: ArticleUserStateSnapshot]
    func fetchUnreadCounts(feedIDs: [UUID]) throws -> [UUID: Int]

    @discardableResult
    func upsert(feedID: UUID, articleExternalID: String, update: ArticleStateUpsert) throws -> ArticleState

    @discardableResult
    func bulkSetRead(feedID: UUID, articleExternalIDs: [String], isRead: Bool, at: Date) throws -> [ArticleState]

    @discardableResult
    func bulkSetStarred(feedID: UUID, articleExternalIDs: [String], isStarred: Bool, at: Date) throws -> [ArticleState]

    @discardableResult
    func bulkSetHidden(feedID: UUID, articleExternalIDs: [String], isHidden: Bool, at: Date) throws -> [ArticleState]

    func save() throws
}

@MainActor
protocol ArticleQueryService {
    func fetchArticleListItems(feedID: UUID, sortMode: ArticleSortMode) throws -> [ArticleListItemDTO]
    func fetchArticleListItems(feedID: UUID, sortMode: ArticleSortMode, filter: ArticleListFilter) throws -> [ArticleListItemDTO]
    func fetchInboxListItems(sortMode: ArticleSortMode) throws -> [ArticleListItemDTO]
    func fetchInboxListItems(sortMode: ArticleSortMode, filter: ArticleListFilter) throws -> [ArticleListItemDTO]
    func fetchReaderArticle(id: UUID) throws -> ReaderArticleDTO?
}

@MainActor
final class SwiftDataArticleStateRepository: ArticleStateRepository, SwiftDataRepositoryContext {
    let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchState(feedID: UUID, articleExternalID: String) throws -> ArticleState? {
        let descriptor = FetchDescriptor<ArticleState>(
            predicate: #Predicate<ArticleState> { articleState in
                articleState.feedID == feedID && articleState.articleExternalID == articleExternalID
            }
        )
        return try fetchFirst(descriptor)
    }

    func fetchOrCreate(feedID: UUID, articleExternalID: String) throws -> ArticleState {
        try fetchOrCreate(feedID: feedID, articleExternalID: articleExternalID, saveAfterCreation: true)
    }

    func fetchStateSnapshot(feedID: UUID, articleExternalID: String) throws -> ArticleUserStateSnapshot? {
        try fetchState(feedID: feedID, articleExternalID: articleExternalID)
            .map(ArticleUserStateSnapshot.init(articleState:))
    }

    func fetchStateSnapshots(feedID: UUID, articleExternalIDs: [String]) throws -> [String: ArticleUserStateSnapshot] {
        let normalizedIDs = normalizedIdentifiers(articleExternalIDs)

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
                snapshotsByCompositeKey[articleCompositeKey(feedID: feedID, articleExternalID: externalID)] = snapshot
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
            let key = articleCompositeKey(feedID: article.feedID, articleExternalID: article.externalID)
            let state = stateSnapshots[key]
            let isHidden = state?.isHidden ?? false
            let isRead = state?.isRead ?? false

            guard isHidden == false, isRead == false else { continue }
            unreadCounts[article.feedID, default: 0] += 1
        }

        return unreadCounts
    }

    @discardableResult
    func upsert(feedID: UUID, articleExternalID: String, update: ArticleStateUpsert) throws -> ArticleState {
        let articleState = try fetchOrCreate(
            feedID: feedID,
            articleExternalID: articleExternalID,
            saveAfterCreation: false
        )
        apply(update, to: articleState)
        try saveIfNeeded()
        return articleState
    }

    @discardableResult
    func bulkSetRead(feedID: UUID, articleExternalIDs: [String], isRead: Bool, at: Date = .now) throws -> [ArticleState] {
        try bulkUpdate(
            feedID: feedID,
            articleExternalIDs: articleExternalIDs,
            update: ArticleStateUpsert(
                isRead: isRead,
                readAt: isRead ? at : nil,
                lastInteractionAt: at,
                updatedAt: at
            )
        )
    }

    @discardableResult
    func bulkSetStarred(feedID: UUID, articleExternalIDs: [String], isStarred: Bool, at: Date = .now) throws -> [ArticleState] {
        try bulkUpdate(
            feedID: feedID,
            articleExternalIDs: articleExternalIDs,
            update: ArticleStateUpsert(
                isStarred: isStarred,
                starredAt: isStarred ? at : nil,
                lastInteractionAt: at,
                updatedAt: at
            )
        )
    }

    @discardableResult
    func bulkSetHidden(feedID: UUID, articleExternalIDs: [String], isHidden: Bool, at: Date = .now) throws -> [ArticleState] {
        try bulkUpdate(
            feedID: feedID,
            articleExternalIDs: articleExternalIDs,
            update: ArticleStateUpsert(
                isHidden: isHidden,
                hiddenAt: isHidden ? at : nil,
                lastInteractionAt: at,
                updatedAt: at
            )
        )
    }

    func save() throws {
        try saveIfNeeded(force: true)
    }

    private func fetchOrCreate(
        feedID: UUID,
        articleExternalID: String,
        saveAfterCreation: Bool
    ) throws -> ArticleState {
        if let existingState = try fetchState(feedID: feedID, articleExternalID: articleExternalID) {
            return existingState
        }

        let articleState = ArticleState(
            articleExternalID: articleExternalID,
            feedID: feedID
        )
        modelContext.insert(articleState)
        if saveAfterCreation {
            try saveIfNeeded()
        }
        return articleState
    }

    private func bulkUpdate(
        feedID: UUID,
        articleExternalIDs: [String],
        update: ArticleStateUpsert
    ) throws -> [ArticleState] {
        let normalizedIDs = normalizedIdentifiers(articleExternalIDs)
        guard normalizedIDs.isEmpty == false else { return [] }

        let articleStates = try normalizedIDs.map { articleExternalID in
            let articleState = try fetchOrCreate(
                feedID: feedID,
                articleExternalID: articleExternalID,
                saveAfterCreation: false
            )
            apply(update, to: articleState)
            return articleState
        }

        try saveIfNeeded()
        return articleStates
    }

    private func apply(_ update: ArticleStateUpsert, to articleState: ArticleState) {
        var didChange = false

        if let isRead = update.isRead, articleState.isRead != isRead {
            articleState.isRead = isRead
            articleState.readAt = isRead ? (update.readAt ?? update.updatedAt) : nil
            didChange = true
        } else if update.isRead == nil, let readAt = update.readAt {
            articleState.readAt = readAt
            didChange = true
        }

        if let isStarred = update.isStarred, articleState.isStarred != isStarred {
            articleState.isStarred = isStarred
            articleState.starredAt = isStarred ? (update.starredAt ?? update.updatedAt) : nil
            didChange = true
        } else if update.isStarred == nil, let starredAt = update.starredAt {
            articleState.starredAt = starredAt
            didChange = true
        }

        if let isHidden = update.isHidden, articleState.isHidden != isHidden {
            articleState.isHidden = isHidden
            articleState.hiddenAt = isHidden ? (update.hiddenAt ?? update.updatedAt) : nil
            didChange = true
        } else if update.isHidden == nil, let hiddenAt = update.hiddenAt {
            articleState.hiddenAt = hiddenAt
            didChange = true
        }

        if let lastInteractionAt = update.lastInteractionAt {
            articleState.lastInteractionAt = lastInteractionAt
            didChange = true
        } else if didChange {
            articleState.lastInteractionAt = update.updatedAt
        }

        if didChange || update.lastInteractionAt != nil {
            articleState.updatedAt = update.updatedAt
        }
    }

}

@MainActor
final class DefaultArticleQueryService: ArticleQueryService {
    private let articleRepository: any ArticleRepository
    private let articleStateRepository: any ArticleStateRepository

    init(
        articleRepository: any ArticleRepository,
        articleStateRepository: any ArticleStateRepository
    ) {
        self.articleRepository = articleRepository
        self.articleStateRepository = articleStateRepository
    }

    func fetchArticleListItems(feedID: UUID, sortMode: ArticleSortMode) throws -> [ArticleListItemDTO] {
        try fetchArticleListItems(feedID: feedID, sortMode: sortMode, filter: .all)
    }

    func fetchArticleListItems(
        feedID: UUID,
        sortMode: ArticleSortMode,
        filter: ArticleListFilter
    ) throws -> [ArticleListItemDTO] {
        let articles = try articleRepository.fetchArticles(feedID: feedID, sortMode: sortMode)
        let stateByCompositeKey = try fetchStateByCompositeKey(for: articles)

        return articles.compactMap { article in
            let state = stateByCompositeKey[articleCompositeKey(feedID: article.feedID, articleExternalID: article.externalID)]
            let item = ArticleListItemDTO(article: article, state: state)
            return matches(filter: filter, item: item) ? item : nil
        }
    }

    func fetchInboxListItems(sortMode: ArticleSortMode) throws -> [ArticleListItemDTO] {
        try fetchInboxListItems(sortMode: sortMode, filter: .all)
    }

    func fetchInboxListItems(sortMode: ArticleSortMode, filter: ArticleListFilter) throws -> [ArticleListItemDTO] {
        let articles = try articleRepository.fetchInbox(sortMode: sortMode)
        let stateByCompositeKey = try fetchStateByCompositeKey(for: articles)

        return articles.compactMap { article in
            let state = stateByCompositeKey[articleCompositeKey(feedID: article.feedID, articleExternalID: article.externalID)]
            let item = ArticleListItemDTO(article: article, state: state)
            return matches(filter: filter, item: item) ? item : nil
        }
    }

    func fetchReaderArticle(id: UUID) throws -> ReaderArticleDTO? {
        guard let article = try articleRepository.fetchArticle(id: id) else { return nil }

        let stateByCompositeKey = try fetchStateByCompositeKey(for: [article])
        let state = stateByCompositeKey[articleCompositeKey(feedID: article.feedID, articleExternalID: article.externalID)]
        return ReaderArticleDTO(article: article, state: state)
    }

    private func fetchStateByCompositeKey(for articles: [Article]) throws -> [String: ArticleUserStateSnapshot] {
        guard articles.isEmpty == false else { return [:] }

        return try articleStateRepository.fetchStateSnapshots(for: articles)
    }

    private func articleCompositeKey(feedID: UUID, articleExternalID: String) -> String {
        "\(feedID.uuidString)|\(articleExternalID)"
    }

    private func matches(filter: ArticleListFilter, item: ArticleListItemDTO) -> Bool {
        switch filter {
        case .all:
            item.isHidden == false
        case .unread:
            item.isHidden == false && item.isRead == false
        case .starred:
            item.isHidden == false && item.isStarred
        case .hidden:
            item.isHidden
        }
    }
}
