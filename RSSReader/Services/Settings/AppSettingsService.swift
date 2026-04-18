import Foundation

struct AppSettingsSnapshot: Equatable, Sendable {
    var defaultReaderMode: ReaderMode
    var selectedSourcesFilterRawValue: String?
    var refreshIntervalPreference: RefreshPreference
    var useiCloudSync: Bool
    var markAsReadOnOpen: Bool
    var askBeforeMarkingAllAsRead: Bool
    var sortMode: ArticleSortMode

    init(
        defaultReaderMode: ReaderMode = .embedded,
        selectedSourcesFilterRawValue: String? = SourcesFilter.allItems.rawValue,
        refreshIntervalPreference: RefreshPreference = .manual,
        useiCloudSync: Bool = false,
        markAsReadOnOpen: Bool = true,
        askBeforeMarkingAllAsRead: Bool = true,
        sortMode: ArticleSortMode = .publishedAtDescending
    ) {
        self.defaultReaderMode = defaultReaderMode
        self.selectedSourcesFilterRawValue = selectedSourcesFilterRawValue
        self.refreshIntervalPreference = refreshIntervalPreference
        self.useiCloudSync = useiCloudSync
        self.markAsReadOnOpen = markAsReadOnOpen
        self.askBeforeMarkingAllAsRead = askBeforeMarkingAllAsRead
        self.sortMode = sortMode
    }

    init(settings: AppSettings) {
        self.init(
            defaultReaderMode: settings.defaultReaderMode,
            selectedSourcesFilterRawValue: settings.selectedSourcesFilterRawValue,
            refreshIntervalPreference: settings.refreshIntervalPreference,
            useiCloudSync: settings.useiCloudSync,
            markAsReadOnOpen: settings.markAsReadOnOpen,
            askBeforeMarkingAllAsRead: settings.askBeforeMarkingAllAsRead,
            sortMode: settings.sortMode
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
    var sortMode: ArticleSortMode? = nil
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
                sortMode: snapshot.sortMode,
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
                sortMode: patch.sortMode,
                updatedAt: patch.updatedAt
            )
        )
        return AppSettingsSnapshot(settings: settings)
    }
}
