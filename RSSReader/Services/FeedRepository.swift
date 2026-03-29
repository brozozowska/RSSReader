import Foundation
import SwiftData

@MainActor
protocol SwiftDataRepositoryContext {
    var modelContext: ModelContext { get }
}

extension SwiftDataRepositoryContext {
    func saveIfNeeded(force: Bool = false) throws {
        guard force || modelContext.hasChanges else { return }
        try modelContext.save()
    }

    func fetchFirst<Model>(_ descriptor: FetchDescriptor<Model>) throws -> Model?
    where Model: PersistentModel {
        var descriptor = descriptor
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func normalizedIdentifier(_ value: String) -> String? {
        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedValue.isEmpty ? nil : normalizedValue
    }

    func normalizedIdentifiers(_ values: [String]) -> [String] {
        Array(Set(values.compactMap(normalizedIdentifier)))
    }

    func articleCompositeKey(feedID: UUID, articleExternalID: String) -> String {
        "\(feedID.uuidString)|\(articleExternalID)"
    }
}

struct FeedFetchMetadata: Sendable {
    let id: UUID
    let url: String
    let siteURL: String?
    let title: String
    let subtitle: String?
    let iconURL: String?
    let language: String?
    let kind: FeedKind
    let isActive: Bool
    let lastFetchedAt: Date?
    let lastSuccessfulFetchAt: Date?
    let lastETag: String?
    let lastModifiedHeader: String?
    let lastSyncError: String?
    let updatedAt: Date

    init(feed: Feed) {
        self.id = feed.id
        self.url = feed.url
        self.siteURL = feed.siteURL
        self.title = feed.title
        self.subtitle = feed.subtitle
        self.iconURL = feed.iconURL
        self.language = feed.language
        self.kind = feed.kind
        self.isActive = feed.isActive
        self.lastFetchedAt = feed.lastFetchedAt
        self.lastSuccessfulFetchAt = feed.lastSuccessfulFetchAt
        self.lastETag = feed.lastETag
        self.lastModifiedHeader = feed.lastModifiedHeader
        self.lastSyncError = feed.lastSyncError
        self.updatedAt = feed.updatedAt
    }
}

struct FeedSidebarItem: Sendable, Identifiable {
    let id: UUID
    let title: String
    let iconURL: String?
    let folderName: String?
    let unreadCount: Int

    init(feed: Feed, unreadCount: Int = 0) {
        self.id = feed.id
        self.title = feed.title
        self.iconURL = feed.iconURL
        self.folderName = feed.folder?.name
        self.unreadCount = unreadCount
    }

    func withUnreadCount(_ unreadCount: Int) -> FeedSidebarItem {
        FeedSidebarItem(
            id: id,
            title: title,
            iconURL: iconURL,
            folderName: folderName,
            unreadCount: unreadCount
        )
    }

    private init(
        id: UUID,
        title: String,
        iconURL: String?,
        folderName: String?,
        unreadCount: Int
    ) {
        self.id = id
        self.title = title
        self.iconURL = iconURL
        self.folderName = folderName
        self.unreadCount = unreadCount
    }
}

struct FeedMetadataUpdate: Sendable {
    var siteURL: String? = nil
    var title: String? = nil
    var subtitle: String? = nil
    var iconURL: String? = nil
    var language: String? = nil
    var kind: FeedKind? = nil
    var lastFetchedAt: Date? = nil
    var lastSuccessfulFetchAt: Date? = nil
    var lastETag: String? = nil
    var lastModifiedHeader: String? = nil
    var lastSyncError: String? = nil
    var updatedAt: Date = .now
}

@MainActor
protocol FeedRepository {
    func fetchFeed(id: UUID) throws -> Feed?
    func fetchFeed(url: String) throws -> Feed?
    func fetchAllFeeds() throws -> [Feed]
    func fetchActiveFeeds() throws -> [Feed]
    func fetchSidebarItems() throws -> [FeedSidebarItem]
    func fetchMetadata(for feedID: UUID) throws -> FeedFetchMetadata?

    @discardableResult
    func insert(_ feed: Feed) throws -> Feed

    @discardableResult
    func updateMetadata(for feedID: UUID, with update: FeedMetadataUpdate) throws -> Feed?

    @discardableResult
    func delete(feedID: UUID) throws -> Bool

    func save() throws
    func delete(_ feed: Feed) throws
}

@MainActor
final class SwiftDataFeedRepository: FeedRepository, SwiftDataRepositoryContext {
    let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchFeed(id: UUID) throws -> Feed? {
        let descriptor = FetchDescriptor<Feed>(
            predicate: #Predicate<Feed> { feed in
                feed.id == id
            }
        )
        return try fetchFirst(descriptor)
    }

    func fetchFeed(url: String) throws -> Feed? {
        let descriptor = FetchDescriptor<Feed>(
            predicate: #Predicate<Feed> { feed in
                feed.url == url
            }
        )
        return try fetchFirst(descriptor)
    }

    func fetchAllFeeds() throws -> [Feed] {
        let descriptor = FetchDescriptor<Feed>(
            sortBy: [
                SortDescriptor(\Feed.title, order: .forward),
                SortDescriptor(\Feed.createdAt, order: .forward)
            ]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchActiveFeeds() throws -> [Feed] {
        let descriptor = FetchDescriptor<Feed>(
            predicate: #Predicate<Feed> { feed in
                feed.isActive
            },
            sortBy: [
                SortDescriptor(\Feed.title, order: .forward),
                SortDescriptor(\Feed.createdAt, order: .forward)
            ]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchSidebarItems() throws -> [FeedSidebarItem] {
        try fetchActiveFeeds().map { feed in
            FeedSidebarItem(feed: feed)
        }
    }

    func fetchMetadata(for feedID: UUID) throws -> FeedFetchMetadata? {
        try fetchFeed(id: feedID).map(FeedFetchMetadata.init(feed:))
    }

    @discardableResult
    func insert(_ feed: Feed) throws -> Feed {
        modelContext.insert(feed)
        try saveIfNeeded()
        return feed
    }

    @discardableResult
    func updateMetadata(for feedID: UUID, with update: FeedMetadataUpdate) throws -> Feed? {
        guard let feed = try fetchFeed(id: feedID) else { return nil }

        if let siteURL = update.siteURL {
            feed.siteURL = siteURL
        }

        if let title = update.title, title.isEmpty == false {
            feed.title = title
        }

        if let subtitle = update.subtitle {
            feed.subtitle = subtitle
        }

        if let iconURL = update.iconURL {
            feed.iconURL = iconURL
        }

        if let language = update.language {
            feed.language = language
        }

        if let kind = update.kind {
            feed.kind = kind
        }

        if let lastFetchedAt = update.lastFetchedAt {
            feed.lastFetchedAt = lastFetchedAt
        }

        if let lastSuccessfulFetchAt = update.lastSuccessfulFetchAt {
            feed.lastSuccessfulFetchAt = lastSuccessfulFetchAt
        }

        if let lastETag = update.lastETag {
            feed.lastETag = lastETag
        }

        if let lastModifiedHeader = update.lastModifiedHeader {
            feed.lastModifiedHeader = lastModifiedHeader
        }

        if let lastSyncError = update.lastSyncError {
            feed.lastSyncError = lastSyncError
        }

        feed.updatedAt = update.updatedAt

        try saveIfNeeded()
        return feed
    }

    func save() throws {
        try saveIfNeeded(force: true)
    }

    func delete(_ feed: Feed) throws {
        try FeedDeletionService.delete(feed, in: modelContext)
    }

    @discardableResult
    func delete(feedID: UUID) throws -> Bool {
        guard let feed = try fetchFeed(id: feedID) else { return false }
        try delete(feed)
        return true
    }
}
