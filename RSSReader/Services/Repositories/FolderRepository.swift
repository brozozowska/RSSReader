import Foundation
import SwiftData

@MainActor
protocol FolderRepository {
    func fetchFolder(id: UUID) throws -> Folder?
    func fetchFolder(name: String) throws -> Folder?
    func fetchAllFolders() throws -> [Folder]

    @discardableResult
    func insert(_ folder: Folder) throws -> Folder

    func save() throws
    func delete(_ folder: Folder) throws
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

    func save() throws {
        try saveIfNeeded(force: true)
    }

    func delete(_ folder: Folder) throws {
        modelContext.delete(folder)
        try saveIfNeeded()
    }
}
