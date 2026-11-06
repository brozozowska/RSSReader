import Foundation
import SwiftData

enum SwiftDataRepositoryOperation: Equatable, Sendable {
    case fetch
    case fetchCount
    case save
}

typealias SwiftDataRepositoryOperationRecorder = (SwiftDataRepositoryOperation) -> Void
typealias SwiftDataRepositorySaveOperation = (ModelContext) throws -> Void

@MainActor
protocol SwiftDataRepositoryContext {
    var modelContext: ModelContext { get }
    var persistenceOperationRecorder: SwiftDataRepositoryOperationRecorder { get }
    var persistenceSaveOperation: SwiftDataRepositorySaveOperation { get }
}

extension SwiftDataRepositoryContext {
    var persistenceOperationRecorder: SwiftDataRepositoryOperationRecorder {
        { _ in }
    }

    var persistenceSaveOperation: SwiftDataRepositorySaveOperation {
        { try $0.save() }
    }

    func saveIfNeeded(force: Bool = false) throws {
        guard force || modelContext.hasChanges else { return }
        persistenceOperationRecorder(.save)
        try persistenceSaveOperation(modelContext)
    }

    func rollbackChanges() {
        modelContext.rollback()
    }

    func fetchFirst<Model>(_ descriptor: FetchDescriptor<Model>) throws -> Model?
    where Model: PersistentModel {
        var descriptor = descriptor
        descriptor.fetchLimit = 1
        return try performFetch(descriptor).first
    }

    func performFetch<Model>(_ descriptor: FetchDescriptor<Model>) throws -> [Model]
    where Model: PersistentModel {
        persistenceOperationRecorder(.fetch)
        return try modelContext.fetch(descriptor)
    }

    func performFetchCount<Model>(_ descriptor: FetchDescriptor<Model>) throws -> Int
    where Model: PersistentModel {
        persistenceOperationRecorder(.fetchCount)
        return try modelContext.fetchCount(descriptor)
    }

    func normalizedIdentifier(_ value: String) -> String? {
        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedValue.isEmpty ? nil : normalizedValue
    }

    func normalizedIdentifiers(_ values: [String]) -> [String] {
        Array(Set(values.compactMap(normalizedIdentifier)))
    }

    func articleCompositeKey(feedID: UUID, articleExternalID: String) -> String {
        ArticleStateIdentity.lookupKey(
            feedID: feedID,
            articleExternalID: articleExternalID
        )
    }
}
