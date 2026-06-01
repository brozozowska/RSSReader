import Foundation
import SwiftData

@Model
final class AppSettings {
    static let singletonKeyValue = "app-settings"

    var id: UUID = UUID()
    var singletonKey: String = AppSettings.singletonKeyValue
    var articleOpeningMode: ArticleOpeningMode = ArticleOpeningMode.feedReader
    var selectedSourcesFilterRawValue: String? = SourcesFilter.allItems.rawValue
    var refreshIntervalPreference: RefreshPreference = RefreshPreference.manual
    var useiCloudSync: Bool = false
    var markAsReadOnOpen: Bool = true
    var askBeforeMarkingAllAsRead: Bool = true
    var showUnreadCountBadge: Bool = false
    var unreadSortMode: ArticleSortMode = ArticleSortMode.publishedAtDescending
    var articleRetentionPolicy: ArticleRetentionPolicy = ArticleRetentionPolicy.oneWeek
    var articleBodyLinkOpeningPolicy: ArticleBodyLinkOpeningPolicy = ArticleBodyLinkOpeningPolicy.inAppBrowser
    var articleSourceLinkOpeningPolicy: ArticleSourceLinkOpeningPolicy = ArticleSourceLinkOpeningPolicy.inAppBrowser
    var readerAdjacentNavigationControlsMode: ReaderAdjacentNavigationControlsMode = ReaderAdjacentNavigationControlsMode.swipesAndToolbarControls
    var interfaceThemeMode: InterfaceThemeMode = InterfaceThemeMode.automaticLightDark
    var lastSourcesRefreshAt: Date?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(
        id: UUID = UUID(),
        singletonKey: String = AppSettings.singletonKeyValue,
        articleOpeningMode: ArticleOpeningMode = .feedReader,
        selectedSourcesFilterRawValue: String? = SourcesFilter.allItems.rawValue,
        refreshIntervalPreference: RefreshPreference = .manual,
        useiCloudSync: Bool = false,
        markAsReadOnOpen: Bool = true,
        askBeforeMarkingAllAsRead: Bool = true,
        showUnreadCountBadge: Bool = false,
        unreadSortMode: ArticleSortMode = .publishedAtDescending,
        articleRetentionPolicy: ArticleRetentionPolicy = .oneWeek,
        articleBodyLinkOpeningPolicy: ArticleBodyLinkOpeningPolicy = .inAppBrowser,
        articleSourceLinkOpeningPolicy: ArticleSourceLinkOpeningPolicy = .inAppBrowser,
        readerAdjacentNavigationControlsMode: ReaderAdjacentNavigationControlsMode = .swipesAndToolbarControls,
        interfaceThemeMode: InterfaceThemeMode = .automaticLightDark,
        lastSourcesRefreshAt: Date? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.singletonKey = singletonKey
        self.articleOpeningMode = articleOpeningMode
        self.selectedSourcesFilterRawValue = selectedSourcesFilterRawValue
        self.refreshIntervalPreference = refreshIntervalPreference
        self.useiCloudSync = useiCloudSync
        self.markAsReadOnOpen = markAsReadOnOpen
        self.askBeforeMarkingAllAsRead = askBeforeMarkingAllAsRead
        self.showUnreadCountBadge = showUnreadCountBadge
        self.unreadSortMode = unreadSortMode
        self.articleRetentionPolicy = articleRetentionPolicy
        self.articleBodyLinkOpeningPolicy = articleBodyLinkOpeningPolicy
        self.articleSourceLinkOpeningPolicy = articleSourceLinkOpeningPolicy
        self.readerAdjacentNavigationControlsMode = readerAdjacentNavigationControlsMode
        self.interfaceThemeMode = interfaceThemeMode
        self.lastSourcesRefreshAt = lastSourcesRefreshAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
