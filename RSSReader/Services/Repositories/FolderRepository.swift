import Foundation
import SwiftData

struct FolderDetailsUpdate: Sendable {
    var name: String? = nil
    var updatedAt: Date = .now
}

@MainActor
protocol FolderRepository {
    func fetchFolder(id: UUID) throws -> Folder?
    func fetchFolder(name: String) throws -> Folder?
    func fetchAllFolders() throws -> [Folder]

    @discardableResult
    func insert(_ folder: Folder) throws -> Folder

    @discardableResult
    func update(
        folderID: UUID,
        with update: FolderDetailsUpdate,
        saveAfterOperation: Bool
    ) throws -> Folder?

    func save() throws
    func delete(_ folder: Folder) throws
}

extension FolderRepository {
    @discardableResult
    func update(folderID: UUID, with update: FolderDetailsUpdate) throws -> Folder? {
        try self.update(folderID: folderID, with: update, saveAfterOperation: true)
    }
}

@MainActor
final class SwiftDataFolderRepository: FolderRepository, SwiftDataRepositoryContext {
    let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchFolder(id: UUID) throws -> Folder? {
        let descriptor = FetchDescriptor<Folder>(
            predicate: #Predicate<Folder> { folder in
                folder.id == id
            }
        )
        return try fetchFirst(descriptor)
    }

    func fetchFolder(name: String) throws -> Folder? {
        let descriptor = FetchDescriptor<Folder>(
            predicate: #Predicate<Folder> { folder in
                folder.name == name
            }
        )
        return try fetchFirst(descriptor)
    }

    func fetchAllFolders() throws -> [Folder] {
        let descriptor = FetchDescriptor<Folder>(
            sortBy: [
                SortDescriptor(\Folder.sortOrder, order: .forward),
                SortDescriptor(\Folder.name, order: .forward),
                SortDescriptor(\Folder.createdAt, order: .forward)
            ]
        )
        return try modelContext.fetch(descriptor)
    }

    @discardableResult
    func insert(_ folder: Folder) throws -> Folder {
        modelContext.insert(folder)
        try saveIfNeeded()
        return folder
    }

    @discardableResult
    func update(
        folderID: UUID,
        with update: FolderDetailsUpdate,
        saveAfterOperation: Bool = true
    ) throws -> Folder? {
        guard let folder = try fetchFolder(id: folderID) else { return nil }

        if let name = update.name, name.isEmpty == false {
            folder.name = name
        }
        folder.updatedAt = update.updatedAt

        if saveAfterOperation {
            try saveIfNeeded()
        }
        return folder
    }

    func save() throws {
        try saveIfNeeded(force: true)
    }

    func delete(_ folder: Folder) throws {
        modelContext.delete(folder)
        try saveIfNeeded()
    }
}
