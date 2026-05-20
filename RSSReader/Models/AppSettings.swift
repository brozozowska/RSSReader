import Foundation
import SwiftData

@Model
final class AppSettings {
    static let singletonKeyValue = "app-settings"

    var id: UUID = UUID()
    var singletonKey: String = AppSettings.singletonKeyValue
    var defaultReaderMode: ReaderMode = ReaderMode.embedded
    var selectedSourcesFilterRawValue: String? = SourcesFilter.allItems.rawValue
    var refreshIntervalPreference: RefreshPreference = RefreshPreference.manual
    var useiCloudSync: Bool = false
    var markAsReadOnOpen: Bool = true
    var askBeforeMarkingAllAsRead: Bool = true
    var sortMode: ArticleSortMode = ArticleSortMode.publishedAtAscending
    var articleRetentionPolicy: ArticleRetentionPolicy = ArticleRetentionPolicy.oneWeek
    var articleBodyLinkOpeningPolicy: ArticleBodyLinkOpeningPolicy = ArticleBodyLinkOpeningPolicy.inAppBrowser
    var articleSourceLinkOpeningPolicy: ArticleSourceLinkOpeningPolicy = ArticleSourceLinkOpeningPolicy.inAppBrowser
    var readerAdjacentNavigationControlsMode: ReaderAdjacentNavigationControlsMode = ReaderAdjacentNavigationControlsMode.swipesAndToolbarControls
    var interfaceThemeMode: InterfaceThemeMode = InterfaceThemeMode.automaticLightDark
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(
        id: UUID = UUID(),
        singletonKey: String = AppSettings.singletonKeyValue,
        defaultReaderMode: ReaderMode = .embedded,
        selectedSourcesFilterRawValue: String? = SourcesFilter.allItems.rawValue,
        refreshIntervalPreference: RefreshPreference = .manual,
        useiCloudSync: Bool = false,
        markAsReadOnOpen: Bool = true,
        askBeforeMarkingAllAsRead: Bool = true,
        sortMode: ArticleSortMode = .publishedAtAscending,
        articleRetentionPolicy: ArticleRetentionPolicy = .oneWeek,
        articleBodyLinkOpeningPolicy: ArticleBodyLinkOpeningPolicy = .inAppBrowser,
        articleSourceLinkOpeningPolicy: ArticleSourceLinkOpeningPolicy = .inAppBrowser,
        readerAdjacentNavigationControlsMode: ReaderAdjacentNavigationControlsMode = .swipesAndToolbarControls,
        interfaceThemeMode: InterfaceThemeMode = .automaticLightDark,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.singletonKey = singletonKey
        self.defaultReaderMode = defaultReaderMode
        self.selectedSourcesFilterRawValue = selectedSourcesFilterRawValue
        self.refreshIntervalPreference = refreshIntervalPreference
        self.useiCloudSync = useiCloudSync
        self.markAsReadOnOpen = markAsReadOnOpen
        self.askBeforeMarkingAllAsRead = askBeforeMarkingAllAsRead
        self.sortMode = sortMode
        self.articleRetentionPolicy = articleRetentionPolicy
        self.articleBodyLinkOpeningPolicy = articleBodyLinkOpeningPolicy
        self.articleSourceLinkOpeningPolicy = articleSourceLinkOpeningPolicy
        self.readerAdjacentNavigationControlsMode = readerAdjacentNavigationControlsMode
        self.interfaceThemeMode = interfaceThemeMode
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
