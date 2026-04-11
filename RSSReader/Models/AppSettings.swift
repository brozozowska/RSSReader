import Foundation
import SwiftData

@Model
final class AppSettings {
    static let singletonKeyValue = "app-settings"

    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var singletonKey: String
    var defaultReaderMode: ReaderMode
    var showUnreadOnly: Bool
    var selectedSourcesFilterRawValue: String?
    var refreshIntervalPreference: RefreshPreference
    var useiCloudSync: Bool
    var markAsReadOnOpen: Bool
    var sortMode: ArticleSortMode
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        singletonKey: String = AppSettings.singletonKeyValue,
        defaultReaderMode: ReaderMode = .embedded,
        showUnreadOnly: Bool = false,
        selectedSourcesFilterRawValue: String? = nil,
        refreshIntervalPreference: RefreshPreference = .manual,
        useiCloudSync: Bool = false,
        markAsReadOnOpen: Bool = true,
        sortMode: ArticleSortMode = .publishedAtDescending,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.singletonKey = singletonKey
        self.defaultReaderMode = defaultReaderMode
        self.showUnreadOnly = showUnreadOnly
        self.selectedSourcesFilterRawValue = selectedSourcesFilterRawValue
        self.refreshIntervalPreference = refreshIntervalPreference
        self.useiCloudSync = useiCloudSync
        self.markAsReadOnOpen = markAsReadOnOpen
        self.sortMode = sortMode
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
