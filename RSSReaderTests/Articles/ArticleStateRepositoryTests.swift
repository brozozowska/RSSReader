import Foundation
import SwiftData
import Testing
@testable import RSSReader

@Suite("Articles / Article State Repository")
@MainActor
struct ArticleStateRepositoryTests {
    @Test
    func articleStateRepositoryCollapsesDuplicateCompositeRowsDuringUpsert() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/state-duplicates.xml"]).first)
        let modelContext = harness.modelContainer.mainContext
        let staleState = ArticleState(
            articleExternalID: "duplicate-article",
            feedID: feed.id,
            isRead: false,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let newerState = ArticleState(
            articleExternalID: "duplicate-article",
            feedID: feed.id,
            isRead: true,
            readAt: Date(timeIntervalSince1970: 200),
            updatedAt: Date(timeIntervalSince1970: 200)
        )

        modelContext.insert(staleState)
        modelContext.insert(newerState)
        try modelContext.save()

        let finalState = try harness.articleStateRepository.upsert(
            feedID: feed.id,
            articleExternalID: "duplicate-article",
            update: ArticleStateUpsert(
                isStarred: true,
                starredAt: Date(timeIntervalSince1970: 300),
                lastInteractionAt: Date(timeIntervalSince1970: 300),
                updatedAt: Date(timeIntervalSince1970: 300)
            )
        )
        let persistedStates = try modelContext.fetch(FetchDescriptor<ArticleState>())

        #expect(persistedStates.count == 1)
        #expect(finalState.id == persistedStates.first?.id)
        #expect(finalState.isRead)
        #expect(finalState.readAt == Date(timeIntervalSince1970: 200))
        #expect(finalState.isStarred)
        #expect(finalState.starredAt == Date(timeIntervalSince1970: 300))
        #expect(finalState.updatedAt == Date(timeIntervalSince1970: 300))
    }

    @Test
    func articleStateRepositoryKeepsNewestDuplicateRowWhenRepairingPreexistingDuplicates() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/state-repair.xml"]).first)
        let modelContext = harness.modelContainer.mainContext
        let olderState = ArticleState(
            articleExternalID: "repair-article",
            feedID: feed.id,
            isRead: false,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let newerState = ArticleState(
            articleExternalID: "repair-article",
            feedID: feed.id,
            isRead: true,
            readAt: Date(timeIntervalSince1970: 200),
            updatedAt: Date(timeIntervalSince1970: 200)
        )

        modelContext.insert(olderState)
        modelContext.insert(newerState)
        try modelContext.save()

        let repairedState = try harness.articleStateRepository.fetchOrCreate(
            feedID: feed.id,
            articleExternalID: "repair-article"
        )
        let persistedStates = try modelContext.fetch(FetchDescriptor<ArticleState>())

        #expect(persistedStates.count == 1)
        #expect(repairedState.id == newerState.id)
        #expect(repairedState.isRead)
        #expect(repairedState.readAt == Date(timeIntervalSince1970: 200))
        #expect(repairedState.updatedAt == Date(timeIntervalSince1970: 200))
    }

    @Test
    func articleStateRepositoryCountsArchivedArticlesAsUnread() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/state-counts.xml"]).first)
        _ = try harness.insertArticle(
            feed: feed,
            externalID: "archived-unread-article",
            url: "https://example.com/state-counts/articles/archived",
            title: "Archived Unread Article",
            archivedAt: .distantPast
        )
        let unreadCounts = try harness.articleStateRepository.fetchUnreadCounts(feedIDs: [feed.id])

        #expect(unreadCounts[feed.id] == 1)
    }
}
