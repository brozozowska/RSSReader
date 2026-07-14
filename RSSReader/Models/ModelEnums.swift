import Foundation

nonisolated enum FeedKind: String, Codable, CaseIterable, Sendable {
    case rss
    case atom
    case unknown
}

enum ArticleOpeningMode: String, Codable, CaseIterable, Sendable {
    case feedReader
    case safariView
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

    init(unreadArticleSortMode: ArticleSortMode) {
        switch unreadArticleSortMode {
        case .publishedAtDescending:
            self = .newestFirst
        case .publishedAtAscending:
            self = .oldestFirst
        }
    }

    var unreadArticleSortMode: ArticleSortMode {
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
