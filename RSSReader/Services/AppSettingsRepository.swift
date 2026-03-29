import Foundation
import SwiftData

struct AppSettingsUpdate: Sendable {
    var defaultReaderMode: ReaderMode? = nil
    var showUnreadOnly: Bool? = nil
    var refreshIntervalPreference: RefreshPreference? = nil
    var useiCloudSync: Bool? = nil
    var markAsReadOnOpen: Bool? = nil
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
final class SwiftDataAppSettingsRepository: AppSettingsRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetch() throws -> AppSettings? {
        var descriptor = FetchDescriptor<AppSettings>(
            predicate: #Predicate<AppSettings> { appSettings in
                appSettings.singletonKey == "app-settings"
            }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
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

        if let showUnreadOnly = update.showUnreadOnly {
            settings.showUnreadOnly = showUnreadOnly
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

    private func saveIfNeeded(force: Bool = false) throws {
        guard force || modelContext.hasChanges else { return }
        try modelContext.save()
    }
}
