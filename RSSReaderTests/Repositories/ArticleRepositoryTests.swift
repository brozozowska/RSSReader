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

        let payloads = try ArticleUpsertPayload.makeAllPrepared(
            entries: [
                makePreparedEntry(
                    externalID: "reactivated-id",
                    url: "https://example.com/reactivated-updated",
                    title: "Reactivated title"
                ),
                makePreparedEntry(
                    externalID: "new-id",
                    url: "https://example.com/new",
                    title: "Initial new title"
                ),
                makePreparedEntry(
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
        #expect(reactivatedArticle.searchableText.contains("Reactivated title"))
        #expect(reactivatedArticle.searchableText.contains("Stale reactivated title") == false)
        #expect(reactivatedArticle.searchableTextVersion == ArticleSearchableTextPolicy.currentVersion)
        #expect(reactivatedArticle.searchableTextSourceUpdatedAt == reactivatedArticle.updatedAt)
        #expect(reactivatedArticle.fetchedAt == fetchedAt)
        #expect(missingArticle.archivedAt == fetchedAt)
        #expect(alreadyArchivedArticle.archivedAt == preservedArchivedAt)
        #expect(insertedArticle.url == "https://example.com/new-updated")
        #expect(insertedArticle.title == "Updated duplicate title")
        #expect(insertedArticle.searchableText.contains("Updated duplicate title"))
        #expect(insertedArticle.searchableText.utf8.count <= ArticleSearchableTextPolicy.maximumUTF8ByteCount)
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
        let canonicalStateUpdatedAt = Date(timeIntervalSince1970: 1_575_000_000)
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
        let staleCurrentState = ArticleState(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
            articleExternalID: "synced-current",
            feedID: feed.id,
            isRead: true,
            readAt: staleUpdatedAt,
            updatedAt: staleUpdatedAt
        )
        let tiedLosingCurrentState = ArticleState(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!,
            articleExternalID: "\nsynced-current",
            feedID: feed.id,
            lastInteractionAt: canonicalStateUpdatedAt,
            updatedAt: canonicalStateUpdatedAt
        )
        let canonicalCurrentState = ArticleState(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000013")!,
            articleExternalID: " synced-current ",
            feedID: feed.id,
            isRead: true,
            readAt: canonicalStateUpdatedAt,
            isStarred: true,
            starredAt: canonicalStateUpdatedAt,
            isHidden: true,
            hiddenAt: canonicalStateUpdatedAt,
            lastInteractionAt: canonicalStateUpdatedAt,
            updatedAt: canonicalStateUpdatedAt
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
        for articleState in [
            staleCurrentState,
            tiedLosingCurrentState,
            canonicalCurrentState
        ] {
            modelContext.insert(articleState)
        }
        try modelContext.save()
        let payloads = try ArticleUpsertPayload.makeAllPrepared(
            entries: [
                makePreparedEntry(
                    externalID: "synced-current",
                    url: "https://example.com/current-refreshed",
                    title: "Refreshed current title"
                ),
                makePreparedEntry(
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
        let firstHiddenQueryItems = try queryService.fetchArticleListItems(
            feedID: feed.id,
            sortMode: .publishedAtDescending,
            filter: .hidden
        )
        let currentQueryItem = try #require(firstHiddenQueryItems.first)
        let currentReaderArticle = try #require(
            try queryService.fetchReaderArticle(id: firstCurrentArticle.id)
        )
        let firstRepairedStates = try modelContext.fetch(FetchDescriptor<ArticleState>())

        #expect(firstRepairedArticles.count == 3)
        #expect(firstCurrentArticle.id == canonicalCurrentArticle.id)
        #expect(firstCurrentArticle.externalID == "synced-current")
        #expect(firstCurrentArticle.title == "Refreshed current title")
        #expect(firstCurrentArticle.archivedAt == nil)
        #expect(firstMissingArticle.id == canonicalMissingArticle.id)
        #expect(firstMissingArticle.archivedAt == preservedArchivedAt)
        #expect(firstRepairedStates.count == 1)
        #expect(firstRepairedStates.first?.id == canonicalCurrentState.id)
        #expect(firstRepairedStates.first?.articleExternalID == "synced-current")
        #expect(firstRepairedStates.first?.updatedAt == canonicalStateUpdatedAt)
        #expect(firstHiddenQueryItems.count == 1)
        #expect(currentQueryItem.articleExternalID == "synced-current")
        #expect(currentQueryItem.isRead)
        #expect(currentQueryItem.isStarred)
        #expect(currentQueryItem.isHidden)
        #expect(currentReaderArticle.isRead)
        #expect(currentReaderArticle.isStarred)
        #expect(currentReaderArticle.isHidden)

        _ = try harness.articleRepository.reconcileFeedSnapshot(
            payloads,
            into: feed,
            fetchedAt: fetchedAt
        )

        let repeatedArticles = try harness.articleRepository.fetchArticles(feedID: feed.id)
        let repeatedHiddenQueryItems = try queryService.fetchArticleListItems(
            feedID: feed.id,
            sortMode: .publishedAtDescending,
            filter: .hidden
        )
        let repeatedStates = try modelContext.fetch(FetchDescriptor<ArticleState>())

        #expect(Set(repeatedArticles.map(\.id)) == Set(firstRepairedArticles.map(\.id)))
        #expect(repeatedArticles.count == 3)
        #expect(repeatedStates.count == 1)
        #expect(repeatedStates.first?.id == canonicalCurrentState.id)
        #expect(repeatedStates.first?.articleExternalID == "synced-current")
        #expect(repeatedHiddenQueryItems.count == 1)
        #expect(repeatedHiddenQueryItems.first?.articleExternalID == "synced-current")
    }

    @Test
    func articleRepositoryStagesArticleStateIdentityRepairInsideSnapshotRollbackBoundary() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try insertFeed(
            into: harness,
            url: "https://example.com/state-rollback-feed.xml"
        )
        let modelContext = harness.modelContainer.mainContext
        let olderUpdatedAt = Date(timeIntervalSince1970: 1_500_000_000)
        let newerUpdatedAt = Date(timeIntervalSince1970: 1_600_000_000)
        let olderArticle = Article(
            feedID: feed.id,
            feedTitle: feed.displayTitle,
            externalID: "rollback-identity",
            url: "https://example.com/articles/rollback-older",
            title: "Older",
            updatedAt: olderUpdatedAt
        )
        let canonicalArticle = Article(
            feedID: feed.id,
            feedTitle: feed.displayTitle,
            externalID: " rollback-identity ",
            url: "https://example.com/articles/rollback-canonical",
            title: "Canonical",
            updatedAt: newerUpdatedAt
        )
        let articleState = ArticleState(
            articleExternalID: " rollback-identity ",
            feedID: feed.id,
            isRead: true,
            readAt: newerUpdatedAt,
            isStarred: true,
            starredAt: newerUpdatedAt,
            lastInteractionAt: newerUpdatedAt,
            updatedAt: newerUpdatedAt
        )
        modelContext.insert(olderArticle)
        modelContext.insert(canonicalArticle)
        modelContext.insert(articleState)
        try modelContext.save()

        _ = try harness.articleRepository.reconcileFeedSnapshot(
            [],
            into: feed,
            fetchedAt: newerUpdatedAt,
            saveAfterOperation: false
        )

        let stagedArticles = try modelContext.fetch(FetchDescriptor<Article>())
        let stagedStates = try modelContext.fetch(FetchDescriptor<ArticleState>())
        #expect(modelContext.hasChanges)
        #expect(stagedArticles.count == 1)
        #expect(stagedArticles.first?.externalID == "rollback-identity")
        #expect(stagedStates.count == 1)
        #expect(stagedStates.first?.articleExternalID == "rollback-identity")

        modelContext.rollback()

        let rolledBackArticles = try modelContext.fetch(FetchDescriptor<Article>())
        let rolledBackStates = try modelContext.fetch(FetchDescriptor<ArticleState>())
        #expect(rolledBackArticles.count == 2)
        #expect(Set(rolledBackArticles.map(\.externalID)) == [
            "rollback-identity",
            " rollback-identity "
        ])
        #expect(rolledBackStates.count == 1)
        #expect(rolledBackStates.first?.articleExternalID == " rollback-identity ")
        #expect(rolledBackStates.first?.isRead == true)
        #expect(rolledBackStates.first?.isStarred == true)
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
        let article = try harness.insertArticle(
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
            try harness.articleRepository.fetchArticle(id: article.id)
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
    func articleRepositoryAppliesScopeStateArchiveAndSortPredicateCombinations() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let newsFolder = try harness.folderRepository.insert(Folder(name: "News", sortOrder: 0))
        let newsFeed = try insertFeed(
            into: harness,
            url: "https://example.com/news.xml",
            folder: newsFolder
        )
        let techFeed = try insertFeed(
            into: harness,
            url: "https://example.com/tech.xml"
        )
        let archivedAt = Date(timeIntervalSince1970: 1_000)

        _ = try harness.insertArticle(
            feed: newsFeed,
            externalID: "news-default",
            url: "https://example.com/news-default",
            title: "News Default",
            publishedAt: Date(timeIntervalSince1970: 600)
        )
        _ = try harness.insertArticle(
            feed: newsFeed,
            externalID: "news-read",
            url: "https://example.com/news-read",
            title: "News Read",
            publishedAt: Date(timeIntervalSince1970: 500)
        )
        _ = try harness.insertArticle(
            feed: newsFeed,
            externalID: "news-starred",
            url: "https://example.com/news-starred",
            title: "News Starred",
            publishedAt: Date(timeIntervalSince1970: 400)
        )
        _ = try harness.insertArticle(
            feed: newsFeed,
            externalID: "news-hidden",
            url: "https://example.com/news-hidden",
            title: "News Hidden",
            publishedAt: Date(timeIntervalSince1970: 300)
        )
        _ = try harness.insertArticle(
            feed: newsFeed,
            externalID: "news-archived-unread",
            url: "https://example.com/news-archived-unread",
            title: "News Archived Unread",
            publishedAt: Date(timeIntervalSince1970: 200),
            archivedAt: archivedAt
        )
        _ = try harness.insertArticle(
            feed: newsFeed,
            externalID: "news-archived-hidden-starred",
            url: "https://example.com/news-archived-hidden-starred",
            title: "News Archived Hidden Starred",
            publishedAt: Date(timeIntervalSince1970: 100),
            archivedAt: archivedAt
        )
        _ = try harness.insertArticle(
            feed: techFeed,
            externalID: "news-starred",
            url: "https://example.com/tech-default",
            title: "Tech Default",
            publishedAt: Date(timeIntervalSince1970: 550)
        )

        try harness.articleStateRepository.upsert(
            feedID: newsFeed.id,
            articleExternalID: "news-read",
            update: ArticleStateUpsert(isRead: true, updatedAt: Date(timeIntervalSince1970: 10))
        )
        try harness.articleStateRepository.upsert(
            feedID: newsFeed.id,
            articleExternalID: "news-starred",
            update: ArticleStateUpsert(
                isRead: true,
                isStarred: true,
                updatedAt: Date(timeIntervalSince1970: 20)
            )
        )
        try harness.articleStateRepository.upsert(
            feedID: newsFeed.id,
            articleExternalID: "news-hidden",
            update: ArticleStateUpsert(isHidden: true, updatedAt: Date(timeIntervalSince1970: 30))
        )
        try harness.articleStateRepository.upsert(
            feedID: newsFeed.id,
            articleExternalID: "news-archived-hidden-starred",
            update: ArticleStateUpsert(
                isRead: true,
                isStarred: true,
                isHidden: true,
                updatedAt: Date(timeIntervalSince1970: 40)
            )
        )

        let currentUnreadInbox = try harness.articleRepository.fetchArticles(
            matching: ArticleQueryCriteria(
                scope: .inbox,
                hidden: .isFalse,
                archived: .isFalse,
                read: .isFalse,
                sortMode: .publishedAtDescending
            )
        )
        let archivedUnreadFolder = try harness.articleRepository.fetchArticles(
            matching: ArticleQueryCriteria(
                scope: .folder("News"),
                hidden: .isFalse,
                archived: .isTrue,
                read: .isFalse,
                sortMode: .publishedAtDescending
            )
        )
        let visibleStarredFeed = try harness.articleRepository.fetchArticles(
            matching: ArticleQueryCriteria(
                scope: .feed(newsFeed.id),
                hidden: .isFalse,
                starred: .isTrue,
                sortMode: .publishedAtDescending
            )
        )
        let starredInbox = try harness.articleRepository.fetchArticles(
            matching: ArticleQueryCriteria(
                scope: .inbox,
                hidden: .isFalse,
                starred: .isTrue,
                sortMode: .publishedAtDescending
            )
        )
        let hiddenReadStarredFolder = try harness.articleRepository.fetchArticles(
            matching: ArticleQueryCriteria(
                scope: .folder("News"),
                hidden: .isTrue,
                read: .isTrue,
                starred: .isTrue,
                sortMode: .publishedAtAscending
            )
        )
        let negativeDefaults = try harness.articleRepository.fetchArticles(
            matching: ArticleQueryCriteria(
                scope: .feed(newsFeed.id),
                hidden: .isFalse,
                read: .isFalse,
                starred: .isFalse,
                sortMode: .publishedAtAscending
            )
        )

        #expect(currentUnreadInbox.map(\.feedID) == [newsFeed.id, techFeed.id])
        #expect(currentUnreadInbox.map(\.externalID) == ["news-default", "news-starred"])
        #expect(archivedUnreadFolder.map(\.externalID) == ["news-archived-unread"])
        #expect(visibleStarredFeed.map(\.externalID) == ["news-starred"])
        #expect(starredInbox.map(\.feedID) == [newsFeed.id])
        #expect(hiddenReadStarredFolder.map(\.externalID) == ["news-archived-hidden-starred"])
        #expect(negativeDefaults.map(\.externalID) == ["news-archived-unread", "news-default"])
    }

    @Test
    func articleRepositoryBuildsStateOverlayOnlyForBoundedQueryIdentityBatches() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let queriedFeed = try insertFeed(
            into: harness,
            url: "https://example.com/batched-query.xml"
        )
        let unrelatedFeed = try insertFeed(
            into: harness,
            url: "https://example.com/unrelated-query.xml"
        )
        let modelContext = harness.modelContainer.mainContext

        for index in 0..<5 {
            _ = try harness.insertArticle(
                feed: queriedFeed,
                externalID: "queried-\(index)",
                url: "https://example.com/queried-\(index)",
                title: "Queried \(index)",
                publishedAt: Date(timeIntervalSince1970: TimeInterval(index))
            )
            modelContext.insert(
                ArticleState(
                    articleExternalID: "queried-\(index)",
                    feedID: queriedFeed.id,
                    isRead: index.isMultiple(of: 2),
                    updatedAt: Date(timeIntervalSince1970: TimeInterval(index))
                )
            )
        }
        _ = try harness.insertArticle(
            feed: unrelatedFeed,
            externalID: "unrelated",
            url: "https://example.com/unrelated",
            title: "Unrelated"
        )
        modelContext.insert(
            ArticleState(
                articleExternalID: "unrelated",
                feedID: unrelatedFeed.id,
                isRead: true
            )
        )
        try modelContext.save()

        var observations: [ArticleStateQueryBatchObservation] = []
        let repository = SwiftDataArticleRepository(
            modelContext: modelContext,
            queryBatchSize: 2,
            articleStateQueryBatchProbe: { observations.append($0) }
        )
        let records = try repository.fetchArticleQueryRecords(
            matching: ArticleQueryCriteria(
                scope: .feed(queriedFeed.id),
                read: .isFalse,
                sortMode: .publishedAtDescending
            )
        )

        #expect(records.map { $0.article.externalID } == ["queried-3", "queried-1"])
        #expect(records.allSatisfy { $0.state?.isRead == false })
        #expect(observations.count == 3)
        #expect(observations.allSatisfy { $0.kind == .overlay })
        #expect(observations.allSatisfy { $0.feedIDs == [queriedFeed.id] })
        #expect(observations.map(\.requestedIdentityCount) == [2, 2, 1])
        #expect(observations.reduce(0) { $0 + $1.materializedStateCount } == 5)
    }

    @Test
    func articleRepositoryStopsAtPageBoundaryBeforeMaterializingRemainingQueryRecords() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try insertFeed(into: harness)
        let modelContext = harness.modelContainer.mainContext

        for index in 0..<6 {
            _ = try harness.insertArticle(
                feed: feed,
                externalID: "paged-\(index)",
                url: "https://example.com/paged-\(index)",
                title: "Paged \(index)",
                publishedAt: Date(timeIntervalSince1970: TimeInterval(index))
            )
            modelContext.insert(
                ArticleState(
                    articleExternalID: "paged-\(index)",
                    feedID: feed.id,
                    isRead: index < 3
                )
            )
        }
        try modelContext.save()

        var observations: [ArticleStateQueryBatchObservation] = []
        let repository = SwiftDataArticleRepository(
            modelContext: modelContext,
            queryBatchSize: 4,
            articleStateQueryBatchProbe: { observations.append($0) }
        )
        let criteria = ArticleQueryCriteria(
            scope: .feed(feed.id),
            read: .isFalse,
            sortMode: .publishedAtDescending
        )

        let firstPage = try repository.fetchArticleQueryRecordPage(
            matching: criteria,
            offset: 0,
            limit: 2
        )

        #expect(firstPage.records.map { $0.article.externalID } == ["paged-5", "paged-4"])
        #expect(firstPage.nextOffset != nil)
        #expect(observations.map(\.requestedIdentityCount) == [3])

        observations.removeAll()
        let secondPage = try repository.fetchArticleQueryRecordPage(
            matching: criteria,
            offset: try #require(firstPage.nextOffset),
            limit: 2
        )

        #expect(secondPage.records.map { $0.article.externalID } == ["paged-3"])
        #expect(secondPage.nextOffset == nil)
        #expect(observations.allSatisfy { $0.requestedIdentityCount <= 3 })
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

    private func makePreparedEntry(
        externalID: String,
        guid: String? = nil,
        url: String,
        canonicalURL: String? = nil,
        title: String,
        summary: String? = nil,
        contentHTML: String? = nil,
        contentText: String? = nil,
        author: String? = nil,
        publishedAt: Date? = nil,
        updatedAt: Date? = nil,
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
            publishedAt: publishedAt,
            updatedAt: updatedAt,
            imageURL: imageURL
        )
    }
}
