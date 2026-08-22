import Foundation
import SwiftData
import Testing
@testable import RSSReader

@Suite("Repositories / Feed")
@MainActor
struct FeedRepositoryTests {
    @Test
    func feedRepositoryReturnsBoundedIdentityBatchesForInboxAndFolderMetrics() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let folder = try harness.folderRepository.insert(Folder(name: "Metric Folder", sortOrder: 0))
        let feeds = try harness.insertFeeds(
            urls: [
                "https://example.com/metric-1.xml",
                "https://example.com/metric-2.xml",
                "https://example.com/metric-3.xml"
            ]
        )
        _ = try harness.feedRepository.updateFolderAssignment(
            for: feeds[0].id,
            with: FeedFolderAssignmentUpdate(folder: folder)
        )
        _ = try harness.feedRepository.updateFolderAssignment(
            for: feeds[2].id,
            with: FeedFolderAssignmentUpdate(folder: folder)
        )
        let operations = SwiftDataRepositoryOperationCounter()
        let repository = SwiftDataFeedRepository(
            modelContext: harness.modelContainer.mainContext,
            persistenceOperationRecorder: operations.record
        )

        let firstInboxBatch = try repository.fetchFeedIDBatch(
            matching: .inbox,
            offset: 0,
            limit: 2
        )
        let secondInboxBatch = try repository.fetchFeedIDBatch(
            matching: .inbox,
            offset: firstInboxBatch.count,
            limit: 2
        )
        let folderBatch = try repository.fetchFeedIDBatch(
            matching: .folder(folder.name),
            offset: 0,
            limit: 1
        )
        let remainingFolderBatch = try repository.fetchFeedIDBatch(
            matching: .folder(folder.name),
            offset: folderBatch.count,
            limit: 1
        )

        #expect(firstInboxBatch.count == 2)
        #expect(secondInboxBatch.count == 1)
        #expect(Set(firstInboxBatch + secondInboxBatch) == Set(feeds.map(\.id)))
        #expect(folderBatch.count == 1)
        #expect(remainingFolderBatch.count == 1)
        #expect(Set(folderBatch + remainingFolderBatch) == Set([feeds[0].id, feeds[2].id]))
        #expect(operations.fetchCount == 4)
        #expect(operations.saveCount == 0)
    }

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

    @Test
    func feedRepositoryRejectsDuplicateURLOnInsertWithoutSchemaLevelUniqueness() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())

        _ = try harness.feedRepository.insert(
            Feed(url: "https://example.com/duplicate.xml", title: "First")
        )

        #expect(throws: RepositoryInvariantViolation.duplicateFeedURL("https://example.com/duplicate.xml")) {
            _ = try harness.feedRepository.insert(
                Feed(url: "https://example.com/duplicate.xml", title: "Second")
            )
        }
    }

    @Test
    func feedRepositoryRejectsDuplicateURLOnUpdateWithoutSchemaLevelUniqueness() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feeds = try harness.insertFeeds(
            urls: [
                "https://example.com/first.xml",
                "https://example.com/second.xml"
            ]
        )
        let firstFeed = try #require(feeds.first)
        let secondFeed = try #require(feeds.last)

        #expect(throws: RepositoryInvariantViolation.duplicateFeedURL(secondFeed.url)) {
            _ = try harness.feedRepository.updateDetails(
                for: firstFeed.id,
                with: FeedDetailsUpdate(url: secondFeed.url)
            )
        }
    }

    @Test
    func feedRepositoryDeleteRemovesLocalArticlesBeforeFeedDisappears() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(
            try harness.insertFeeds(urls: ["https://example.com/delete-feed.xml"]).first
        )

        _ = try harness.insertArticle(
            feed: feed,
            externalID: "article-1",
            url: "https://example.com/articles/1",
            title: "Article One"
        )

        let deleted = try harness.feedRepository.delete(feedID: feed.id)
        let remainingArticles = try harness.articleRepository.fetchArticles(feedID: feed.id)

        #expect(deleted)
        #expect(remainingArticles.isEmpty)
        #expect(try harness.feedRepository.fetchFeed(id: feed.id) == nil)
    }
}
