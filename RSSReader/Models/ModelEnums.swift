import Foundation

enum FeedKind: String, Codable, CaseIterable, Sendable {
    case rss
    case atom
    case unknown
}

enum ReaderMode: String, Codable, CaseIterable, Sendable {
    case embedded
    case reader
    case browser
}

enum RefreshPreference: String, Codable, CaseIterable, Sendable {
    case manual
    case every15Minutes
    case hourly
    case every6Hours
    case daily
}

enum ArticleSortMode: String, Codable, CaseIterable, Sendable {
    case publishedAtDescending
    case publishedAtAscending
}

enum ArticleListSortOrder: String, CaseIterable, Sendable {
    case newestFirst
    case oldestFirst

    init(sortMode: ArticleSortMode) {
        switch sortMode {
        case .publishedAtDescending:
            self = .newestFirst
        case .publishedAtAscending:
            self = .oldestFirst
        }
    }

    var sortMode: ArticleSortMode {
        switch self {
        case .newestFirst:
            .publishedAtDescending
        case .oldestFirst:
            .publishedAtAscending
        }
    }
}

enum ArticleBodyLinkOpeningPolicy: String, Codable, CaseIterable, Sendable {
    case inAppBrowser
    case externalBrowser
}
