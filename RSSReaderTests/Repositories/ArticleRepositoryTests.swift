import Foundation
import SwiftData
import Testing
@testable import RSSReader

@Suite("Repositories / Article")
@MainActor
struct ArticleRepositoryTests {
    @Test
    func articleRepositoryReconcilesProjectionArchiveStateAndMixedPayloadsFromSingleFeedSnapshot() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let folder = try harness.folderRepository.insert(Folder(name: "News", sortOrder: 0))
        let feed = try insertFeed(into: harness)
        let otherFeed = try insertFeed(into: harness, url: "https://other.example.com/feed.xml")
        let fetchedAt = Date(timeIntervalSince1970: 1_700_000_600)
        let preservedArchivedAt = Date(timeIntervalSince1970: 1_600_000_000)
        let reactivatedArticle = try harness.insertArticle(
            feed: feed,
            externalID: " reactivated-id ",
            url: "https://example.com/reactivated",
            title: "Stale reactivated title",
            archivedAt: .distantPast
        )
        let missingArticle = try harness.insertArticle(
            feed: feed,
            externalID: "missing-id",
            url: "https://example.com/missing",
            title: "Missing title"
        )
        let alreadyArchivedArticle = try harness.insertArticle(
            feed: feed,
            externalID: "already-archived-id",
            url: "https://example.com/already-archived",
            title: "Already archived title",
            archivedAt: preservedArchivedAt
        )
        let otherFeedArticle = try harness.insertArticle(
            feed: otherFeed,
            externalID: "reactivated-id",
            url: "https://other.example.com/reactivated",
            title: "Other feed title"
        )
        feed.displayTitleOverride = "Display Feed"
        feed.siteURL = "https://new.example.com/"
        feed.folder = folder

        let payloads = try ArticleUpsertPayload.makeAll(
            entries: [
                makeEntry(
                    externalID: "reactivated-id",
                    url: "https://example.com/reactivated-updated",
                    title: "Reactivated title"
                ),
                makeEntry(
                    externalID: "new-id",
                    url: "https://example.com/new",
                    title: "Initial new title"
                ),
                makeEntry(
                    externalID: " new-id ",
                    url: "https://example.com/new-updated",
                    title: "Updated duplicate title"
                )
            ],
            fetchedAt: fetchedAt
        )
        let result = try harness.articleRepository.reconcileFeedSnapshot(
            payloads,
            into: feed,
            fetchedAt: fetchedAt
        )

        let persistedArticles = try harness.articleRepository.fetchArticles(feedID: feed.id)
        let insertedArticle = try #require(persistedArticles.first { $0.externalID == "new-id" })

        #expect(result.projectionUpdateCount == 9)
        #expect(result.reconciledArticleCount == 2)
        #expect(result.upsertedArticleCount == 2)
        #expect(persistedArticles.count == 4)
        #expect(reactivatedArticle.archivedAt == nil)
        #expect(reactivatedArticle.url == "https://example.com/reactivated-updated")
        #expect(reactivatedArticle.title == "Reactivated title")
        #expect(reactivatedArticle.fetchedAt == fetchedAt)
        #expect(missingArticle.archivedAt == fetchedAt)
        #expect(alreadyArchivedArticle.archivedAt == preservedArchivedAt)
        #expect(insertedArticle.url == "https://example.com/new-updated")
        #expect(insertedArticle.title == "Updated duplicate title")
        #expect(insertedArticle.fetchedAt == fetchedAt)
        #expect(otherFeedArticle.title == "Other feed title")
        #expect(persistedArticles.allSatisfy { $0.feedTitle == "Display Feed" })
        #expect(persistedArticles.allSatisfy { $0.feedSiteURL == "https://new.example.com/" })
        #expect(persistedArticles.allSatisfy { $0.feedFolderName == "News" })
    }

    @Test
    func articleRepositoryRepairsSyncedDuplicatesDeterministicallyWithoutLosingArchiveOrUserState() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try insertFeed(into: harness)
        let modelContext = harness.modelContainer.mainContext
        let fetchedAt = Date(timeIntervalSince1970: 1_700_000_600)
        let preservedArchivedAt = Date(timeIntervalSince1970: 1_600_000_000)
        let staleUpdatedAt = Date(timeIntervalSince1970: 1_500_000_000)
        let canonicalUpdatedAt = Date(timeIntervalSince1970: 1_550_000_000)
        let staleCurrentArticle = Article(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            feedID: feed.id,
            feedTitle: feed.displayTitle,
            externalID: "synced-current",
            url: "https://example.com/current-stale",
            title: "Stale current title",
            updatedAt: staleUpdatedAt
        )
        let canonicalCurrentArticle = Article(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            feedID: feed.id,
            feedTitle: feed.displayTitle,
            externalID: " synced-current ",
            url: "https://example.com/current-canonical",
            title: "Canonical current title",
            archivedAt: .distantPast,
            updatedAt: canonicalUpdatedAt
        )
        let tiedCurrentArticle = Article(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            feedID: feed.id,
            feedTitle: feed.displayTitle,
            externalID: "synced-current",
            url: "https://example.com/current-tied",
            title: "Tied current title",
            updatedAt: canonicalUpdatedAt
        )
        let staleMissingArticle = Article(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
            feedID: feed.id,
            feedTitle: feed.displayTitle,
            externalID: "synced-missing",
            url: "https://example.com/missing-stale",
            title: "Stale missing title",
            updatedAt: staleUpdatedAt
        )
        let canonicalMissingArticle = Article(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!,
            feedID: feed.id,
            feedTitle: feed.displayTitle,
            externalID: "synced-missing",
            url: "https://example.com/missing-canonical",
            title: "Canonical missing title",
            archivedAt: preservedArchivedAt,
            updatedAt: canonicalUpdatedAt
        )
        let stableArticle = Article(
            feedID: feed.id,
            feedTitle: feed.displayTitle,
            externalID: "stable",
            url: "https://example.com/stable",
            title: "Stable title",
            updatedAt: canonicalUpdatedAt
        )

        for article in [
            staleCurrentArticle,
            canonicalCurrentArticle,
            tiedCurrentArticle,
            staleMissingArticle,
            canonicalMissingArticle,
            stableArticle
        ] {
            modelContext.insert(article)
        }
        try modelContext.save()

        _ = try harness.articleStateRepository.upsert(
            feedID: feed.id,
            articleExternalID: "synced-current",
            update: ArticleStateUpsert(
                isRead: true,
                readAt: staleUpdatedAt,
                isStarred: true,
                starredAt: canonicalUpdatedAt,
                lastInteractionAt: canonicalUpdatedAt,
                updatedAt: canonicalUpdatedAt
            )
        )
        let payloads = try ArticleUpsertPayload.makeAll(
            entries: [
                makeEntry(
                    externalID: "synced-current",
                    url: "https://example.com/current-refreshed",
                    title: "Refreshed current title"
                ),
                makeEntry(
                    externalID: "stable",
                    url: "https://example.com/stable",
                    title: "Stable title"
                )
            ],
            fetchedAt: fetchedAt
        )

        _ = try harness.articleRepository.reconcileFeedSnapshot(
            payloads,
            into: feed,
            fetchedAt: fetchedAt
        )

        let firstRepairedArticles = try harness.articleRepository.fetchArticles(feedID: feed.id)
        let firstCurrentArticle = try #require(
            firstRepairedArticles.first { $0.externalID == "synced-current" }
        )
        let firstMissingArticle = try #require(
            firstRepairedArticles.first { $0.externalID == "synced-missing" }
        )
        let queryService = DefaultArticleQueryService(
            articleRepository: harness.articleRepository,
            articleStateRepository: harness.articleStateRepository
        )
        let firstQueryItems = try queryService.fetchArticleListItems(
            feedID: feed.id,
            sortMode: .publishedAtDescending
        )
        let currentQueryItem = try #require(
            firstQueryItems.first { $0.articleExternalID == "synced-current" }
        )

        #expect(firstRepairedArticles.count == 3)
        #expect(firstCurrentArticle.id == canonicalCurrentArticle.id)
        #expect(firstCurrentArticle.externalID == "synced-current")
        #expect(firstCurrentArticle.title == "Refreshed current title")
        #expect(firstCurrentArticle.archivedAt == nil)
        #expect(firstMissingArticle.id == canonicalMissingArticle.id)
        #expect(firstMissingArticle.archivedAt == preservedArchivedAt)
        #expect(firstQueryItems.count == 3)
        #expect(firstQueryItems.filter { $0.articleExternalID == "synced-current" }.count == 1)
        #expect(currentQueryItem.isRead)
        #expect(currentQueryItem.isStarred)

        _ = try harness.articleRepository.reconcileFeedSnapshot(
            payloads,
            into: feed,
            fetchedAt: fetchedAt
        )

        let repeatedArticles = try harness.articleRepository.fetchArticles(feedID: feed.id)
        let repeatedQueryItems = try queryService.fetchArticleListItems(
            feedID: feed.id,
            sortMode: .publishedAtDescending
        )

        #expect(Set(repeatedArticles.map(\.id)) == Set(firstRepairedArticles.map(\.id)))
        #expect(repeatedArticles.count == 3)
        #expect(repeatedQueryItems.count == 3)
        #expect(repeatedQueryItems.filter { $0.articleExternalID == "synced-current" }.count == 1)
    }

    @Test
    func articleRepositoryRefreshFeedProjectionUpdatesStoredFeedFields() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let folder = try harness.folderRepository.insert(Folder(name: "News", sortOrder: 0))
        let feed = try insertFeed(
            into: harness,
            title: "Original Feed",
            siteURL: "https://old.example.com/",
            folder: nil
        )
        _ = try harness.insertArticle(
            feed: feed,
            externalID: "article-1",
            url: "https://example.com/articles/1",
            title: "Article"
        )

        feed.title = "Updated Feed"
        feed.displayTitleOverride = "Display Feed"
        feed.siteURL = "https://new.example.com/"
        feed.folder = folder

        let updatedCount = try harness.articleRepository.refreshFeedProjection(for: feed)
        let persistedArticle = try #require(
            try harness.articleRepository.fetchArticle(feedID: feed.id, externalID: "article-1")
        )

        #expect(updatedCount == 3)
        #expect(persistedArticle.feedTitle == "Display Feed")
        #expect(persistedArticle.feedSiteURL == "https://new.example.com/")
        #expect(persistedArticle.feedFolderName == "News")
    }

    @Test
    func articleRepositoryFetchesFeedAndInboxUsingPublishedAtSortModes() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let firstFeed = try insertFeed(into: harness, url: "https://example.com/first.xml")
        let secondFeed = try insertFeed(into: harness, url: "https://example.com/second.xml")

        _ = try harness.insertArticle(
            feed: firstFeed,
            externalID: "old",
            url: "https://example.com/old",
            title: "Old",
            publishedAt: Date(timeIntervalSince1970: 100)
        )
        _ = try harness.insertArticle(
            feed: firstFeed,
            externalID: "new",
            url: "https://example.com/new",
            title: "New",
            publishedAt: Date(timeIntervalSince1970: 300)
        )
        _ = try harness.insertArticle(
            feed: secondFeed,
            externalID: "other-feed",
            url: "https://example.com/other",
            title: "Other Feed",
            publishedAt: Date(timeIntervalSince1970: 200)
        )

        let firstFeedDescending = try harness.articleRepository.fetchArticles(
            feedID: firstFeed.id,
            sortMode: .publishedAtDescending
        )
        let firstFeedAscending = try harness.articleRepository.fetchArticles(
            feedID: firstFeed.id,
            sortMode: .publishedAtAscending
        )
        let inboxDescending = try harness.articleRepository.fetchInbox(sortMode: .publishedAtDescending)

        #expect(firstFeedDescending.map { $0.externalID } == ["new", "old"])
        #expect(firstFeedAscending.map { $0.externalID } == ["old", "new"])
        #expect(inboxDescending.map { $0.externalID } == ["new", "other-feed", "old"])
    }

    @Test
    func articleRepositoryDeleteBatchRemovesOnlyRequestedArticles() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try insertFeed(into: harness)
        let firstArticle = try harness.insertArticle(
            feed: feed,
            externalID: "delete-1",
            url: "https://example.com/delete-1",
            title: "Delete One"
        )
        let secondArticle = try harness.insertArticle(
            feed: feed,
            externalID: "delete-2",
            url: "https://example.com/delete-2",
            title: "Delete Two"
        )
        let keptArticle = try harness.insertArticle(
            feed: feed,
            externalID: "keep",
            url: "https://example.com/keep",
            title: "Keep"
        )

        try harness.articleRepository.delete([firstArticle, secondArticle])

        let remainingArticles = try harness.articleRepository.fetchArticles(feedID: feed.id)
        #expect(remainingArticles.map { $0.externalID } == [keptArticle.externalID])
    }

    @Test
    func articleRepositoryFetchesStableFeedScopedRetentionBatches() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let firstFeed = try insertFeed(into: harness, url: "https://example.com/retention-first.xml")
        let secondFeed = try insertFeed(into: harness, url: "https://example.com/retention-second.xml")
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

        for index in 0..<5 {
            _ = try harness.insertArticle(
                feed: firstFeed,
                externalID: "first-\(index)",
                url: "https://example.com/first-\(index)",
                title: "First \(index)",
                archivedAt: index.isMultiple(of: 2) ? baseDate : nil,
                createdAt: baseDate.addingTimeInterval(TimeInterval(index))
            )
        }
        _ = try harness.insertArticle(
            feed: secondFeed,
            externalID: "other-feed",
            url: "https://example.com/other-feed",
            title: "Other Feed",
            createdAt: baseDate
        )

        let firstBatch = try harness.articleRepository.fetchRetentionBatch(
            feedID: firstFeed.id,
            scope: .all,
            offset: 0,
            limit: 2
        )
        let secondBatch = try harness.articleRepository.fetchRetentionBatch(
            feedID: firstFeed.id,
            scope: .all,
            offset: 2,
            limit: 2
        )
        let archivedBatch = try harness.articleRepository.fetchRetentionBatch(
            feedID: firstFeed.id,
            scope: .archived,
            offset: 1,
            limit: 2
        )

        #expect(firstBatch.map(\.externalID) == ["first-0", "first-1"])
        #expect(secondBatch.map(\.externalID) == ["first-2", "first-3"])
        #expect(archivedBatch.map(\.externalID) == ["first-2", "first-4"])
    }

    private func insertFeed(
        into harness: TestHarness,
        url: String = "https://example.com/feed.xml",
        title: String = "Example Feed",
        siteURL: String? = "https://example.com/",
        folder: Folder? = nil
    ) throws -> Feed {
        try harness.feedRepository.insert(
            Feed(
                url: url,
                siteURL: siteURL,
                title: title,
                folder: folder
            )
        )
    }

    private func makeEntry(
        externalID: String,
        guid: String? = nil,
        url: String,
        canonicalURL: String? = nil,
        title: String,
        summary: String? = nil,
        contentHTML: String? = nil,
        contentText: String? = nil,
        author: String? = nil,
        publishedAtRaw: String? = nil,
        updatedAtRaw: String? = nil,
        imageURL: String? = nil
    ) -> ParsedFeedEntryDTO {
        ParsedFeedEntryDTO(
            externalID: externalID,
            guid: guid,
            url: url,
            canonicalURL: canonicalURL,
            title: title,
            summary: summary,
            contentHTML: contentHTML,
            contentText: contentText,
            author: author,
            publishedAtRaw: publishedAtRaw,
            updatedAtRaw: updatedAtRaw,
            imageURL: imageURL
        )
    }
}
