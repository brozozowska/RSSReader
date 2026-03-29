import Foundation
import SwiftData

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
    func fetchMetadata(for feedID: UUID) throws -> FeedFetchMetadata?

    @discardableResult
    func insert(_ feed: Feed) throws -> Feed

    @discardableResult
    func updateMetadata(for feedID: UUID, with update: FeedMetadataUpdate) throws -> Feed?

    func save() throws
    func delete(_ feed: Feed) throws
}

@MainActor
final class SwiftDataFeedRepository: FeedRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchFeed(id: UUID) throws -> Feed? {
        var descriptor = FetchDescriptor<Feed>(
            predicate: #Predicate<Feed> { feed in
                feed.id == id
            }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func fetchFeed(url: String) throws -> Feed? {
        var descriptor = FetchDescriptor<Feed>(
            predicate: #Predicate<Feed> { feed in
                feed.url == url
            }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
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

    private func saveIfNeeded(force: Bool = false) throws {
        guard force || modelContext.hasChanges else { return }
        try modelContext.save()
    }
}
