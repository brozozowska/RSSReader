import Foundation
import Testing
@testable import RSSReader

@Suite("Repositories / Feed")
@MainActor
struct FeedRepositoryTests {
    @Test
    func feedRepositoryUpdatesFolderAssignmentThroughExplicitPersistencePath() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let folderRepository = try #require(harness.dependencies.folderRepository)
        let feed = try #require(
            try harness.insertFeeds(urls: ["https://example.com/folder-assignment.xml"]).first
        )
        let newsFolder = try folderRepository.insert(Folder(name: "News", sortOrder: 0))
        let newsAssignmentDate = Date(timeIntervalSince1970: 100)
        let ungroupedAssignmentDate = Date(timeIntervalSince1970: 200)

        let newsAssignedFeed = try harness.feedRepository.updateFolderAssignment(
            for: feed.id,
            with: FeedFolderAssignmentUpdate(
                folder: newsFolder,
                updatedAt: newsAssignmentDate
            )
        )
        let newsPersistedFeed = try harness.feedRepository.fetchFeed(id: feed.id)

        #expect(newsAssignedFeed?.folder?.id == newsFolder.id)
        #expect(newsAssignedFeed?.updatedAt == newsAssignmentDate)
        #expect(newsPersistedFeed?.folder?.id == newsFolder.id)

        let ungroupedFeed = try harness.feedRepository.updateFolderAssignment(
            for: feed.id,
            with: FeedFolderAssignmentUpdate(
                folder: nil,
                updatedAt: ungroupedAssignmentDate
            )
        )
        let ungroupedPersistedFeed = try harness.feedRepository.fetchFeed(id: feed.id)

        #expect(ungroupedFeed?.folder == nil)
        #expect(ungroupedFeed?.updatedAt == ungroupedAssignmentDate)
        #expect(ungroupedPersistedFeed?.folder == nil)
    }
}
