import Foundation
import SwiftData

@MainActor
protocol FeedFetchLogRepository {
    func fetchLogs(feedID: UUID, limit: Int?) throws -> [FeedFetchLog]
    func fetchLatestLog(feedID: UUID) throws -> FeedFetchLog?

    @discardableResult
    func insert(_ entry: FeedFetchLogEntry) throws -> FeedFetchLog

    @discardableResult
    func insert(_ entries: [FeedFetchLogEntry]) throws -> [FeedFetchLog]

    @discardableResult
    func insert(_ log: FeedFetchLog) throws -> FeedFetchLog

    @discardableResult
    func insert(_ logs: [FeedFetchLog]) throws -> [FeedFetchLog]

    func save() throws
}

@MainActor
final class SwiftDataFeedFetchLogRepository: FeedFetchLogRepository, SwiftDataRepositoryContext {
    let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchLogs(feedID: UUID, limit: Int? = nil) throws -> [FeedFetchLog] {
        var descriptor = FetchDescriptor<FeedFetchLog>(
            predicate: #Predicate<FeedFetchLog> { log in
                log.feedID == feedID
            },
            sortBy: [
                SortDescriptor(\FeedFetchLog.createdAt, order: .reverse)
            ]
        )

        if let limit {
            descriptor.fetchLimit = limit
        }

        return try modelContext.fetch(descriptor)
    }

    func fetchLatestLog(feedID: UUID) throws -> FeedFetchLog? {
        try fetchLogs(feedID: feedID, limit: 1).first
    }

    @discardableResult
    func insert(_ entry: FeedFetchLogEntry) throws -> FeedFetchLog {
        let log = FeedFetchLog(entry: entry)
        modelContext.insert(log)
        try saveIfNeeded()
        return log
    }

    @discardableResult
    func insert(_ entries: [FeedFetchLogEntry]) throws -> [FeedFetchLog] {
        let logs = entries.map(FeedFetchLog.init(entry:))
        for log in logs {
            modelContext.insert(log)
        }
        try saveIfNeeded()
        return logs
    }

    @discardableResult
    func insert(_ log: FeedFetchLog) throws -> FeedFetchLog {
        modelContext.insert(log)
        try saveIfNeeded()
        return log
    }

    @discardableResult
    func insert(_ logs: [FeedFetchLog]) throws -> [FeedFetchLog] {
        for log in logs {
            modelContext.insert(log)
        }
        try saveIfNeeded()
        return logs
    }

    func save() throws {
        try saveIfNeeded(force: true)
    }
}
