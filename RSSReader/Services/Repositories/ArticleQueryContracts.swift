import Foundation

enum ArticleQueryScope: Equatable, Sendable {
    case inbox
    case folder(String)
    case feed(UUID)
}

enum ArticleQueryBooleanFilter: Equatable, Sendable {
    case any
    case isFalse
    case isTrue

    func matches(_ value: Bool) -> Bool {
        switch self {
        case .any:
            true
        case .isFalse:
            value == false
        case .isTrue:
            value
        }
    }
}

struct ArticleQueryCriteria: Equatable, Sendable {
    let scope: ArticleQueryScope
    let hidden: ArticleQueryBooleanFilter
    let archived: ArticleQueryBooleanFilter
    let read: ArticleQueryBooleanFilter
    let starred: ArticleQueryBooleanFilter
    let sortMode: ArticleSortMode

    init(
        scope: ArticleQueryScope,
        hidden: ArticleQueryBooleanFilter = .any,
        archived: ArticleQueryBooleanFilter = .any,
        read: ArticleQueryBooleanFilter = .any,
        starred: ArticleQueryBooleanFilter = .any,
        sortMode: ArticleSortMode
    ) {
        self.scope = scope
        self.hidden = hidden
        self.archived = archived
        self.read = read
        self.starred = starred
        self.sortMode = sortMode
    }
}

struct ArticleQueryCursor: Equatable, Sendable {
    let sortDate: Date
    let articleID: UUID
}

struct ArticleQueryRecord {
    let article: Article
    let state: ArticleUserStateSnapshot?
    let continuationCursor: ArticleQueryCursor
}

struct ArticleQueryRecordScanBatch {
    let records: [ArticleQueryRecord]
    let nextCursor: ArticleQueryCursor?
    let scannedCandidateCount: Int
}

typealias ArticleQueryCancellationCheck = @MainActor () throws -> Void
