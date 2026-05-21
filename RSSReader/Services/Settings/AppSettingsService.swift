import Foundation

struct AppSettingsSnapshot: Equatable, Sendable {
    var defaultReaderMode: ReaderMode
    var selectedSourcesFilterRawValue: String?
    var refreshIntervalPreference: RefreshPreference
    var useiCloudSync: Bool
    var markAsReadOnOpen: Bool
    var askBeforeMarkingAllAsRead: Bool
    var showUnreadCountBadge: Bool
    var sortMode: ArticleSortMode
    var articleRetentionPolicy: ArticleRetentionPolicy
    var articleBodyLinkOpeningPolicy: ArticleBodyLinkOpeningPolicy
    var articleSourceLinkOpeningPolicy: ArticleSourceLinkOpeningPolicy
    var readerAdjacentNavigationControlsMode: ReaderAdjacentNavigationControlsMode
    var interfaceThemeMode: InterfaceThemeMode

    init(
        defaultReaderMode: ReaderMode = .embedded,
        selectedSourcesFilterRawValue: String? = SourcesFilter.allItems.rawValue,
        refreshIntervalPreference: RefreshPreference = .manual,
        useiCloudSync: Bool = false,
        markAsReadOnOpen: Bool = true,
        askBeforeMarkingAllAsRead: Bool = true,
        showUnreadCountBadge: Bool = false,
        sortMode: ArticleSortMode = .publishedAtAscending,
        articleRetentionPolicy: ArticleRetentionPolicy = .oneWeek,
        articleBodyLinkOpeningPolicy: ArticleBodyLinkOpeningPolicy = .inAppBrowser,
        articleSourceLinkOpeningPolicy: ArticleSourceLinkOpeningPolicy = .inAppBrowser,
        readerAdjacentNavigationControlsMode: ReaderAdjacentNavigationControlsMode = .swipesAndToolbarControls,
        interfaceThemeMode: InterfaceThemeMode = .automaticLightDark
    ) {
        self.defaultReaderMode = defaultReaderMode
        self.selectedSourcesFilterRawValue = selectedSourcesFilterRawValue
        self.refreshIntervalPreference = refreshIntervalPreference
        self.useiCloudSync = useiCloudSync
        self.markAsReadOnOpen = markAsReadOnOpen
        self.askBeforeMarkingAllAsRead = askBeforeMarkingAllAsRead
        self.showUnreadCountBadge = showUnreadCountBadge
        self.sortMode = sortMode
        self.articleRetentionPolicy = articleRetentionPolicy
        self.articleBodyLinkOpeningPolicy = articleBodyLinkOpeningPolicy
        self.articleSourceLinkOpeningPolicy = articleSourceLinkOpeningPolicy
        self.readerAdjacentNavigationControlsMode = readerAdjacentNavigationControlsMode
        self.interfaceThemeMode = interfaceThemeMode
    }

    init(settings: AppSettings) {
        self.init(
            defaultReaderMode: settings.defaultReaderMode,
            selectedSourcesFilterRawValue: settings.selectedSourcesFilterRawValue,
            refreshIntervalPreference: settings.refreshIntervalPreference,
            useiCloudSync: settings.useiCloudSync,
            markAsReadOnOpen: settings.markAsReadOnOpen,
            askBeforeMarkingAllAsRead: settings.askBeforeMarkingAllAsRead,
            showUnreadCountBadge: settings.showUnreadCountBadge,
            sortMode: settings.sortMode,
            articleRetentionPolicy: settings.articleRetentionPolicy,
            articleBodyLinkOpeningPolicy: settings.articleBodyLinkOpeningPolicy,
            articleSourceLinkOpeningPolicy: settings.articleSourceLinkOpeningPolicy,
            readerAdjacentNavigationControlsMode: settings.readerAdjacentNavigationControlsMode,
            interfaceThemeMode: settings.interfaceThemeMode
        )
    }
}

struct AppSettingsPatch: Sendable {
    var defaultReaderMode: ReaderMode? = nil
    var selectedSourcesFilterRawValue: String? = nil
    var refreshIntervalPreference: RefreshPreference? = nil
    var useiCloudSync: Bool? = nil
    var markAsReadOnOpen: Bool? = nil
    var askBeforeMarkingAllAsRead: Bool? = nil
    var showUnreadCountBadge: Bool? = nil
    var sortMode: ArticleSortMode? = nil
    var articleRetentionPolicy: ArticleRetentionPolicy? = nil
    var articleBodyLinkOpeningPolicy: ArticleBodyLinkOpeningPolicy? = nil
    var articleSourceLinkOpeningPolicy: ArticleSourceLinkOpeningPolicy? = nil
    var readerAdjacentNavigationControlsMode: ReaderAdjacentNavigationControlsMode? = nil
    var interfaceThemeMode: InterfaceThemeMode? = nil
    var updatedAt: Date = .now
}

@MainActor
protocol AppSettingsService {
    func fetchSettings() throws -> AppSettingsSnapshot

    @discardableResult
    func saveSettings(
        _ snapshot: AppSettingsSnapshot,
        updatedAt: Date
    ) throws -> AppSettingsSnapshot

    @discardableResult
    func updateSettings(_ patch: AppSettingsPatch) throws -> AppSettingsSnapshot
}

@MainActor
final class DefaultAppSettingsService: AppSettingsService {
    private let repository: any AppSettingsRepository

    init(repository: any AppSettingsRepository) {
        self.repository = repository
    }

    func fetchSettings() throws -> AppSettingsSnapshot {
        AppSettingsSnapshot(settings: try repository.fetchOrCreate())
    }

    @discardableResult
    func saveSettings(
        _ snapshot: AppSettingsSnapshot,
        updatedAt: Date = .now
    ) throws -> AppSettingsSnapshot {
        let settings = try repository.update(
            AppSettingsUpdate(
                defaultReaderMode: snapshot.defaultReaderMode,
                selectedSourcesFilterRawValue: snapshot.selectedSourcesFilterRawValue,
                refreshIntervalPreference: snapshot.refreshIntervalPreference,
                useiCloudSync: snapshot.useiCloudSync,
                markAsReadOnOpen: snapshot.markAsReadOnOpen,
                askBeforeMarkingAllAsRead: snapshot.askBeforeMarkingAllAsRead,
                showUnreadCountBadge: snapshot.showUnreadCountBadge,
                sortMode: snapshot.sortMode,
                articleRetentionPolicy: snapshot.articleRetentionPolicy,
                articleBodyLinkOpeningPolicy: snapshot.articleBodyLinkOpeningPolicy,
                articleSourceLinkOpeningPolicy: snapshot.articleSourceLinkOpeningPolicy,
                readerAdjacentNavigationControlsMode: snapshot.readerAdjacentNavigationControlsMode,
                interfaceThemeMode: snapshot.interfaceThemeMode,
                updatedAt: updatedAt
            )
        )
        return AppSettingsSnapshot(settings: settings)
    }

    @discardableResult
    func updateSettings(_ patch: AppSettingsPatch) throws -> AppSettingsSnapshot {
        let settings = try repository.update(
            AppSettingsUpdate(
                defaultReaderMode: patch.defaultReaderMode,
                selectedSourcesFilterRawValue: patch.selectedSourcesFilterRawValue,
                refreshIntervalPreference: patch.refreshIntervalPreference,
                useiCloudSync: patch.useiCloudSync,
                markAsReadOnOpen: patch.markAsReadOnOpen,
                askBeforeMarkingAllAsRead: patch.askBeforeMarkingAllAsRead,
                showUnreadCountBadge: patch.showUnreadCountBadge,
                sortMode: patch.sortMode,
                articleRetentionPolicy: patch.articleRetentionPolicy,
                articleBodyLinkOpeningPolicy: patch.articleBodyLinkOpeningPolicy,
                articleSourceLinkOpeningPolicy: patch.articleSourceLinkOpeningPolicy,
                readerAdjacentNavigationControlsMode: patch.readerAdjacentNavigationControlsMode,
                interfaceThemeMode: patch.interfaceThemeMode,
                updatedAt: patch.updatedAt
            )
        )
        return AppSettingsSnapshot(settings: settings)
    }
}
