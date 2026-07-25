import Foundation
import SwiftData
import Testing
@testable import RSSReader

@Suite("Repositories / Article")
@MainActor
struct ArticleRepositoryTests {
    @Test
    func articleRepositoryUpsertCreatesAndUpdatesWithoutDuplicates() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try insertFeed(into: harness)
        let initialFetchedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let updatedFetchedAt = Date(timeIntervalSince1970: 1_700_000_600)

        let createdArticle = try harness.articleRepository.upsert(
            makeEntry(
                externalID: "article-1",
                guid: "guid-1",
                url: "https://example.com/articles/1",
                title: "Original title",
                summary: "Original summary",
                publishedAtRaw: "Tue, 02 Jan 2024 10:00:00 +0000"
            ),
            into: feed,
            fetchedAt: initialFetchedAt
        )
        let updatedArticle = try harness.articleRepository.upsert(
            makeEntry(
                externalID: "article-1",
                guid: "guid-1-updated",
                url: "https://example.com/articles/1-updated",
                title: "Updated title",
                summary: "Updated summary",
                contentHTML: "<p>Updated HTML</p>",
                author: "Updated Author",
                publishedAtRaw: "Tue, 02 Jan 2024 09:00:00 +0000",
                imageURL: "https://example.com/image.jpg"
            ),
            into: feed,
            fetchedAt: updatedFetchedAt
        )

        let persistedArticles = try harness.articleRepository.fetchArticles(feedID: feed.id)
        let persistedArticle = try #require(persistedArticles.first)

        #expect(createdArticle?.id == updatedArticle?.id)
        #expect(persistedArticles.count == 1)
        #expect(persistedArticle.externalID == "article-1")
        #expect(persistedArticle.guid == "guid-1-updated")
        #expect(persistedArticle.url == "https://example.com/articles/1-updated")
        #expect(persistedArticle.title == "Updated title")
        #expect(persistedArticle.summary == "Updated summary")
        #expect(persistedArticle.contentHTML == "<p>Updated HTML</p>")
        #expect(persistedArticle.author == "Updated Author")
        #expect(persistedArticle.imageURL == "https://example.com/image.jpg")
        #expect(persistedArticle.fetchedAt == updatedFetchedAt)
    }

    @Test
    func articleRepositoryBatchUpsertMixesInsertUpdateAndNormalizedDuplicatesWithoutDuplicateRows() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try insertFeed(into: harness)
        let otherFeed = try insertFeed(into: harness, url: "https://other.example.com/feed.xml")
        let existingArticle = try harness.insertArticle(
            feed: feed,
            externalID: " existing-id ",
            url: "https://example.com/existing",
            title: "Existing title"
        )
        let otherFeedArticle = try harness.insertArticle(
            feed: otherFeed,
            externalID: "existing-id",
            url: "https://other.example.com/existing",
            title: "Other feed title"
        )
        let fetchedAt = Date(timeIntervalSince1970: 1_700_000_600)

        let upsertedArticles = try harness.articleRepository.upsert(
            [
                makeEntry(
                    externalID: "existing-id",
                    url: "https://example.com/existing-updated",
                    title: "Updated existing title"
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
            into: feed,
            fetchedAt: fetchedAt
        )

        let persistedArticles = try harness.articleRepository.fetchArticles(feedID: feed.id)
        let insertedArticle = try #require(persistedArticles.first { $0.externalID == "new-id" })

        #expect(upsertedArticles.map(\.id) == [existingArticle.id, insertedArticle.id])
        #expect(persistedArticles.count == 2)
        #expect(existingArticle.externalID == " existing-id ")
        #expect(existingArticle.url == "https://example.com/existing-updated")
        #expect(existingArticle.title == "Updated existing title")
        #expect(existingArticle.fetchedAt == fetchedAt)
        #expect(insertedArticle.url == "https://example.com/new-updated")
        #expect(insertedArticle.title == "Updated duplicate title")
        #expect(insertedArticle.fetchedAt == fetchedAt)
        #expect(otherFeedArticle.title == "Other feed title")
    }

    @Test
    func articleRepositoryBatchUpsertRejectsNonPersistableEntryWithoutPartialInsert() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try insertFeed(into: harness)
        let validEntry = makeEntry(
            externalID: "valid-id",
            url: "https://example.com/valid",
            title: "Valid title"
        )
        let missingExternalIDEntry = ParsedFeedEntryDTO(
            url: "https://example.com/missing-external-id",
            title: "Missing external ID"
        )

        #expect(
            throws: ArticleUpsertPayloadConstructionError.nonPersistableEntry(index: 1)
        ) {
            _ = try harness.articleRepository.upsert(
                [validEntry, missingExternalIDEntry],
                into: feed,
                fetchedAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
        }

        let persistedArticles = try harness.articleRepository.fetchArticles(feedID: feed.id)
        #expect(persistedArticles.isEmpty)
    }

    @Test
    func articleRepositoryReconcilesProjectionArchiveStateAndUpsertFromSingleFeedSnapshot() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let folder = try harness.folderRepository.insert(Folder(name: "News", sortOrder: 0))
        let feed = try insertFeed(into: harness)
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
        #expect(reactivatedArticle.title == "Reactivated title")
        #expect(missingArticle.archivedAt == fetchedAt)
        #expect(alreadyArchivedArticle.archivedAt == preservedArchivedAt)
        #expect(insertedArticle.title == "Updated duplicate title")
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
    func articleRepositoryReconcileArchivesMissingArticlesAndReactivatesKeptArticles() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try insertFeed(into: harness)
        let firstFetchedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let secondFetchedAt = Date(timeIntervalSince1970: 1_700_000_600)
        let archivedArticle = try harness.insertArticle(
            feed: feed,
            externalID: "archived",
            url: "https://example.com/archived",
            title: "Archived"
        )
        let keptArticle = try harness.insertArticle(
            feed: feed,
            externalID: "kept",
            url: "https://example.com/kept",
            title: "Kept"
        )

        let firstReconcileCount = try harness.articleRepository.reconcileArticles(
            feedID: feed.id,
            keepingExternalIDs: ["kept"],
            fetchedAt: firstFetchedAt
        )

        #expect(firstReconcileCount == 1)
        #expect(archivedArticle.archivedAt == firstFetchedAt)
        #expect(keptArticle.archivedAt == nil)

        let secondReconcileCount = try harness.articleRepository.reconcileArticles(
            feedID: feed.id,
            keepingExternalIDs: [" archived ", "kept"],
            fetchedAt: secondFetchedAt
        )

        #expect(secondReconcileCount == 1)
        #expect(archivedArticle.archivedAt == nil)
        #expect(keptArticle.archivedAt == nil)
    }

    @Test
    func articleRepositoryFetchesFeedAndInboxUsingPublishedAtSortModes() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let firstFeed = try insertFeed(into: harness, url: "https://example.com/first.xml")
        let secondFeed = try insertFeed(into: harness, url: "https://example.com/second.xml")

        _ = try harness.articleRepository.upsert(
            makeEntry(
                externalID: "old",
                url: "https://example.com/old",
                title: "Old",
                publishedAtRaw: "Tue, 02 Jan 2024 09:00:00 +0000"
            ),
            into: firstFeed,
            fetchedAt: Date(timeIntervalSince1970: 100)
        )
        _ = try harness.articleRepository.upsert(
            makeEntry(
                externalID: "new",
                url: "https://example.com/new",
                title: "New",
                publishedAtRaw: "Tue, 02 Jan 2024 11:00:00 +0000"
            ),
            into: firstFeed,
            fetchedAt: Date(timeIntervalSince1970: 200)
        )
        _ = try harness.articleRepository.upsert(
            makeEntry(
                externalID: "other-feed",
                url: "https://example.com/other",
                title: "Other Feed",
                publishedAtRaw: "Tue, 02 Jan 2024 10:00:00 +0000"
            ),
            into: secondFeed,
            fetchedAt: Date(timeIntervalSince1970: 150)
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
