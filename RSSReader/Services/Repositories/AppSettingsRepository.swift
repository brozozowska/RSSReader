import Foundation
import SwiftData

struct AppSettingsUpdate: Sendable {
    var articleOpeningMode: ArticleOpeningMode? = nil
    var selectedSourcesFilterRawValue: String? = nil
    var refreshIntervalPreference: RefreshPreference? = nil
    var useiCloudSync: Bool? = nil
    var markAsReadOnOpen: Bool? = nil
    var askBeforeMarkingAllAsRead: Bool? = nil
    var showUnreadCountBadge: Bool? = nil
    var unreadSortMode: ArticleSortMode? = nil
    var articleRetentionPolicy: ArticleRetentionPolicy? = nil
    var articleBodyLinkOpeningPolicy: ArticleBodyLinkOpeningPolicy? = nil
    var articleSourceLinkOpeningPolicy: ArticleSourceLinkOpeningPolicy? = nil
    var readerAdjacentNavigationControlsMode: ReaderAdjacentNavigationControlsMode? = nil
    var interfaceThemeMode: InterfaceThemeMode? = nil
    var lastSourcesRefreshAt: Date? = nil
    var updatedAt: Date = .now
}

@MainActor
protocol AppSettingsRepository {
    func fetch() throws -> AppSettings?
    func fetchOrCreate() throws -> AppSettings

    @discardableResult
    func update(_ update: AppSettingsUpdate) throws -> AppSettings

    func save() throws
}

@MainActor
final class SwiftDataAppSettingsRepository: AppSettingsRepository, SwiftDataRepositoryContext {
    let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetch() throws -> AppSettings? {
        try fetchSingletonSettings().first
    }

    func fetchOrCreate() throws -> AppSettings {
        if let existingSettings = try fetch() {
            try removeDuplicateSingletonSettings(keeping: existingSettings)
            return existingSettings
        }

        let settings = AppSettings()
        modelContext.insert(settings)
        try saveIfNeeded()
        return settings
    }

    @discardableResult
    func update(_ update: AppSettingsUpdate) throws -> AppSettings {
        let settings = try fetchOrCreate()

        if let articleOpeningMode = update.articleOpeningMode {
            settings.articleOpeningMode = articleOpeningMode
        }

        if let selectedSourcesFilterRawValue = update.selectedSourcesFilterRawValue {
            settings.selectedSourcesFilterRawValue = selectedSourcesFilterRawValue
        }

        if let refreshIntervalPreference = update.refreshIntervalPreference {
            settings.refreshIntervalPreference = refreshIntervalPreference
        }

        if let useiCloudSync = update.useiCloudSync {
            settings.useiCloudSync = useiCloudSync
        }

        if let markAsReadOnOpen = update.markAsReadOnOpen {
            settings.markAsReadOnOpen = markAsReadOnOpen
        }

        if let askBeforeMarkingAllAsRead = update.askBeforeMarkingAllAsRead {
            settings.askBeforeMarkingAllAsRead = askBeforeMarkingAllAsRead
        }

        if let showUnreadCountBadge = update.showUnreadCountBadge {
            settings.showUnreadCountBadge = showUnreadCountBadge
        }

        if let unreadSortMode = update.unreadSortMode {
            settings.unreadSortMode = unreadSortMode
        }

        if let articleRetentionPolicy = update.articleRetentionPolicy {
            settings.articleRetentionPolicy = articleRetentionPolicy
        }

        if let articleBodyLinkOpeningPolicy = update.articleBodyLinkOpeningPolicy {
            settings.articleBodyLinkOpeningPolicy = articleBodyLinkOpeningPolicy
        }

        if let articleSourceLinkOpeningPolicy = update.articleSourceLinkOpeningPolicy {
            settings.articleSourceLinkOpeningPolicy = articleSourceLinkOpeningPolicy
        }

        if let readerAdjacentNavigationControlsMode = update.readerAdjacentNavigationControlsMode {
            settings.readerAdjacentNavigationControlsMode = readerAdjacentNavigationControlsMode
        }

        if let interfaceThemeMode = update.interfaceThemeMode {
            settings.interfaceThemeMode = interfaceThemeMode
        }

        if let lastSourcesRefreshAt = update.lastSourcesRefreshAt {
            settings.lastSourcesRefreshAt = lastSourcesRefreshAt
        }

        settings.updatedAt = update.updatedAt

        try saveIfNeeded()
        return settings
    }

    func save() throws {
        try saveIfNeeded(force: true)
    }

    private func fetchSingletonSettings() throws -> [AppSettings] {
        let descriptor = FetchDescriptor<AppSettings>(
            predicate: #Predicate<AppSettings> { appSettings in
                appSettings.singletonKey == "app-settings"
            },
            sortBy: [
                SortDescriptor(\AppSettings.updatedAt, order: .reverse),
                SortDescriptor(\AppSettings.createdAt, order: .reverse)
            ]
        )
        return try modelContext.fetch(descriptor)
    }

    private func removeDuplicateSingletonSettings(keeping canonicalSettings: AppSettings) throws {
        let duplicateSettings = try fetchSingletonSettings().filter { $0 !== canonicalSettings }
        guard duplicateSettings.isEmpty == false else { return }

        for settings in duplicateSettings {
            modelContext.delete(settings)
        }
        try saveIfNeeded()
    }
}
