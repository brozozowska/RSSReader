import Foundation
import SwiftData

struct RepositoryBatchDeleteResult: Equatable, Sendable {
    let inspectedCount: Int
    let deletedCount: Int
    let processedBatchCount: Int
    let maximumMaterializedBatchCount: Int
}

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

    func deleteLogs(
        olderThan cutoffDate: Date,
        batchSize: Int
    ) throws -> RepositoryBatchDeleteResult
    func deleteLogsExceedingPerFeedCount(
        _ maximumCountPerFeed: Int,
        batchSize: Int
    ) throws -> RepositoryBatchDeleteResult
    func save() throws
    func rollback()
}

@MainActor
final class SwiftDataFeedFetchLogRepository: FeedFetchLogRepository, SwiftDataRepositoryContext {
    let modelContext: ModelContext
    let persistenceSaveOperation: SwiftDataRepositorySaveOperation

    init(
        modelContext: ModelContext,
        persistenceSaveOperation: @escaping SwiftDataRepositorySaveOperation = { try $0.save() }
    ) {
        self.modelContext = modelContext
        self.persistenceSaveOperation = persistenceSaveOperation
    }

    func fetchLogs(feedID: UUID, limit: Int? = nil) throws -> [FeedFetchLog] {
        var descriptor = FetchDescriptor<FeedFetchLog>(
            predicate: #Predicate<FeedFetchLog> { log in
                log.feedID == feedID
            },
            sortBy: [
                SortDescriptor(\FeedFetchLog.createdAt, order: .reverse),
                SortDescriptor(\FeedFetchLog.id, order: .reverse)
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

    func deleteLogs(
        olderThan cutoffDate: Date,
        batchSize: Int
    ) throws -> RepositoryBatchDeleteResult {
        precondition(batchSize > 0)
        var deletedCount = 0
        var processedBatchCount = 0
        var maximumMaterializedBatchCount = 0

        while true {
            try Task.checkCancellation()
            var descriptor = FetchDescriptor<FeedFetchLog>(
                predicate: #Predicate<FeedFetchLog> { log in
                    log.createdAt < cutoffDate
                },
                sortBy: [
                    SortDescriptor(\FeedFetchLog.createdAt, order: .forward),
                    SortDescriptor(\FeedFetchLog.id, order: .forward)
                ]
            )
            descriptor.fetchLimit = batchSize
            let logs = try modelContext.fetch(descriptor)
            guard logs.isEmpty == false else { break }

            processedBatchCount += 1
            maximumMaterializedBatchCount = max(maximumMaterializedBatchCount, logs.count)
            for log in logs {
                modelContext.delete(log)
            }
            try saveIfNeeded()
            deletedCount += logs.count
        }

        return RepositoryBatchDeleteResult(
            inspectedCount: deletedCount,
            deletedCount: deletedCount,
            processedBatchCount: processedBatchCount,
            maximumMaterializedBatchCount: maximumMaterializedBatchCount
        )
    }

    func deleteLogsExceedingPerFeedCount(
        _ maximumCountPerFeed: Int,
        batchSize: Int
    ) throws -> RepositoryBatchDeleteResult {
        precondition(maximumCountPerFeed > 0)
        precondition(batchSize > 0)

        var offset = 0
        var inspectedCount = 0
        var deletedCount = 0
        var processedBatchCount = 0
        var maximumMaterializedBatchCount = 0
        var currentFeedID: UUID?
        var retainedCountForCurrentFeed = 0

        while true {
            try Task.checkCancellation()
            var descriptor = FetchDescriptor<FeedFetchLog>(
                sortBy: [
                    SortDescriptor(\FeedFetchLog.feedID, order: .forward),
                    SortDescriptor(\FeedFetchLog.createdAt, order: .reverse),
                    SortDescriptor(\FeedFetchLog.id, order: .reverse)
                ]
            )
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = batchSize
            let logs = try modelContext.fetch(descriptor)
            guard logs.isEmpty == false else { break }

            processedBatchCount += 1
            maximumMaterializedBatchCount = max(maximumMaterializedBatchCount, logs.count)
            var retainedCountInBatch = 0

            for log in logs {
                inspectedCount += 1
                if currentFeedID != log.feedID {
                    currentFeedID = log.feedID
                    retainedCountForCurrentFeed = 0
                }

                guard retainedCountForCurrentFeed < maximumCountPerFeed else {
                    modelContext.delete(log)
                    deletedCount += 1
                    continue
                }

                retainedCountForCurrentFeed += 1
                retainedCountInBatch += 1
            }

            try saveIfNeeded()
            offset += retainedCountInBatch
        }

        return RepositoryBatchDeleteResult(
            inspectedCount: inspectedCount,
            deletedCount: deletedCount,
            processedBatchCount: processedBatchCount,
            maximumMaterializedBatchCount: maximumMaterializedBatchCount
        )
    }

    func save() throws {
        try saveIfNeeded(force: true)
    }

    func rollback() {
        rollbackChanges()
    }
}
