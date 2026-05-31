import Foundation

enum FeedKind: String, Codable, CaseIterable, Sendable {
    case rss
    case atom
    case unknown
}

enum ReaderMode: String, Codable, CaseIterable, Sendable {
    case embedded
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

enum ArticleRetentionPolicy: String, Codable, CaseIterable, Sendable {
    case currentFeedOnly
    case twoDays
    case oneWeek
    case twoWeeks
    case oneMonth
}

enum UnreadArticleSortOrder: String, CaseIterable, Sendable {
    case newestFirst
    case oldestFirst

    init(unreadSortMode: ArticleSortMode) {
        switch unreadSortMode {
        case .publishedAtDescending:
            self = .newestFirst
        case .publishedAtAscending:
            self = .oldestFirst
        }
    }

    var unreadSortMode: ArticleSortMode {
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

enum ArticleSourceLinkOpeningPolicy: String, Codable, CaseIterable, Sendable {
    case inAppBrowser
    case externalBrowser
}

enum ReaderAdjacentNavigationControlsMode: String, Codable, CaseIterable, Sendable {
    case toolbarControlsOnly
    case swipesOnly
    case swipesAndToolbarControls
}

enum InterfaceThemeMode: String, Codable, CaseIterable, Sendable {
    case automaticLightDark
    case automaticLightBlack
    case light
    case dark
    case black
}
