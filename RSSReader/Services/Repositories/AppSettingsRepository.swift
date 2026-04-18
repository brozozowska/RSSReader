import Foundation
import SwiftData

struct AppSettingsUpdate: Sendable {
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
        let descriptor = FetchDescriptor<AppSettings>(
            predicate: #Predicate<AppSettings> { appSettings in
                appSettings.singletonKey == "app-settings"
            }
        )
        return try fetchFirst(descriptor)
    }

    func fetchOrCreate() throws -> AppSettings {
        if let existingSettings = try fetch() {
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

        if let defaultReaderMode = update.defaultReaderMode {
            settings.defaultReaderMode = defaultReaderMode
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

        if let sortMode = update.sortMode {
            settings.sortMode = sortMode
        }

        settings.updatedAt = update.updatedAt

        try saveIfNeeded()
        return settings
    }

    func save() throws {
        try saveIfNeeded(force: true)
    }
}
