import Testing
@testable import RSSReader

@Suite("Repositories / Folder")
@MainActor
struct FolderRepositoryTests {
    @Test
    func folderRepositoryPersistsInsertedFoldersAndReturnsSortedList() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.folderRepository)

        _ = try repository.insert(Folder(name: "Archive", sortOrder: 2))
        _ = try repository.insert(Folder(name: "News", sortOrder: 0))
        _ = try repository.insert(Folder(name: "Tech", sortOrder: 1))

        let folders = try repository.fetchAllFolders()
        let techFolder = try repository.fetchFolder(name: "Tech")

        #expect(folders.map(\.name) == ["News", "Tech", "Archive"])
        #expect(folders.map(\.sortOrder) == [0, 1, 2])
        #expect(techFolder?.sortOrder == 1)
    }

    @Test
    func folderRepositoryRejectsDuplicateNameOnInsertWithoutSchemaLevelUniqueness() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())

        _ = try harness.folderRepository.insert(Folder(name: "News", sortOrder: 0))

        #expect(throws: RepositoryInvariantViolation.duplicateFolderName("News")) {
            _ = try harness.folderRepository.insert(Folder(name: "News", sortOrder: 1))
        }
    }

    @Test
    func folderRepositoryRejectsDuplicateNameOnUpdateWithoutSchemaLevelUniqueness() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let firstFolder = try harness.folderRepository.insert(Folder(name: "News", sortOrder: 0))
        let secondFolder = try harness.folderRepository.insert(Folder(name: "Tech", sortOrder: 1))

        #expect(throws: RepositoryInvariantViolation.duplicateFolderName(secondFolder.name)) {
            _ = try harness.folderRepository.update(
                folderID: firstFolder.id,
                with: FolderDetailsUpdate(name: secondFolder.name)
            )
        }
    }
}
