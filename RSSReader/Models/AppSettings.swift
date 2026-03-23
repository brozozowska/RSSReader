import Foundation
import SwiftData

@Model
final class AppSettings {
    @Attribute(.unique) var id: UUID
    var defaultReaderMode: ReaderMode
    var showUnreadOnly: Bool
    var refreshIntervalPreference: RefreshPreference
    var useiCloudSync: Bool
    var markAsReadOnOpen: Bool
    var sortMode: ArticleSortMode
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        defaultReaderMode: ReaderMode = .embedded,
        showUnreadOnly: Bool = false,
        refreshIntervalPreference: RefreshPreference = .manual,
        useiCloudSync: Bool = false,
        markAsReadOnOpen: Bool = true,
        sortMode: ArticleSortMode = .publishedAtDescending,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.defaultReaderMode = defaultReaderMode
        self.showUnreadOnly = showUnreadOnly
        self.refreshIntervalPreference = refreshIntervalPreference
        self.useiCloudSync = useiCloudSync
        self.markAsReadOnOpen = markAsReadOnOpen
        self.sortMode = sortMode
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
