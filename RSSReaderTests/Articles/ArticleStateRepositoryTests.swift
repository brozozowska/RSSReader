import Foundation
import SwiftData
import Testing
@testable import RSSReader

@Suite("Articles / Article State Repository")
@MainActor
struct ArticleStateRepositoryTests {
    @Test
    func articleStateSchemaIndexesProductionIdentityPredicatesWithoutArticleLookupProjection() throws {
        let schema = AppComposition.persistenceModelPartition.schema
        let articleStateEntity = try #require(
            schema.entities.first { $0.name == String(describing: ArticleState.self) }
        )
        let articleEntity = try #require(
            schema.entities.first { $0.name == String(describing: Article.self) }
        )

        #expect(
            articleStateEntity.indices.contains([
                "binary",
                "feedID",
                "articleExternalID",
                "updatedAt"
            ])
        )
        #expect(articleEntity.indices.contains(["binary", "feedID", "externalID"]))
        #expect(articleEntity.indices.contains(["binary", "querySortDate"]))
        #expect(articleEntity.indices.contains(["binary", "feedID", "querySortDate"]))
        #expect(articleEntity.indices.contains(["binary", "feedFolderName", "querySortDate"]))
        #expect(articleEntity.attributesByName["stateLookupKey"] == nil)
    }

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
    func articleStateRepositoryCountsArchivedArticlesAsUnreadWhileTheyRemainOnDevice() throws {
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

    @Test
    func articleStateRepositoryUsesBatchedStateScanAndGroupedArticleCounts() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feeds = try harness.insertFeeds(
            urls: [
                "https://example.com/count-one.xml",
                "https://example.com/count-two.xml"
            ]
        )
        let firstFeed = try #require(feeds.first)
        let secondFeed = try #require(feeds.last)
        let modelContext = harness.modelContainer.mainContext

        for externalID in ["default-unread", "newer-unread", "hidden", "read", "archived-unread"] {
            _ = try harness.insertArticle(
                feed: firstFeed,
                externalID: externalID,
                url: "https://example.com/\(externalID)",
                title: externalID,
                archivedAt: externalID == "archived-unread" ? .distantPast : nil
            )
        }
        for externalID in ["second-unread", "second-read"] {
            _ = try harness.insertArticle(
                feed: secondFeed,
                externalID: externalID,
                url: "https://example.com/\(externalID)",
                title: externalID
            )
        }

        modelContext.insert(ArticleState(
            articleExternalID: "hidden",
            feedID: firstFeed.id,
            isHidden: true,
            updatedAt: Date(timeIntervalSince1970: 10)
        ))
        modelContext.insert(ArticleState(
            articleExternalID: "read",
            feedID: firstFeed.id,
            isRead: true,
            updatedAt: Date(timeIntervalSince1970: 20)
        ))
        modelContext.insert(ArticleState(
            articleExternalID: "newer-unread",
            feedID: firstFeed.id,
            isRead: true,
            updatedAt: Date(timeIntervalSince1970: 30)
        ))
        modelContext.insert(ArticleState(
            articleExternalID: "newer-unread",
            feedID: firstFeed.id,
            isRead: false,
            updatedAt: Date(timeIntervalSince1970: 40)
        ))
        modelContext.insert(ArticleState(
            articleExternalID: "orphan-read",
            feedID: firstFeed.id,
            isRead: true,
            updatedAt: Date(timeIntervalSince1970: 50)
        ))
        modelContext.insert(ArticleState(
            articleExternalID: "second-read",
            feedID: secondFeed.id,
            isRead: true,
            updatedAt: Date(timeIntervalSince1970: 60)
        ))
        try modelContext.save()

        let operations = SwiftDataRepositoryOperationCounter()
        var observations: [ArticleStateQueryBatchObservation] = []
        let repository = SwiftDataArticleStateRepository(
            modelContext: modelContext,
            persistenceOperationRecorder: operations.record,
            queryBatchSize: 2,
            queryBatchProbe: { observations.append($0) }
        )

        let aggregateCounts = try repository.fetchAggregateCounts(
            feedIDs: [firstFeed.id, secondFeed.id, firstFeed.id]
        )

        #expect(aggregateCounts.unreadByFeedID[firstFeed.id] == 3)
        #expect(aggregateCounts.unreadByFeedID[secondFeed.id] == 1)
        #expect(aggregateCounts.starredByFeedID[firstFeed.id] == 0)
        #expect(aggregateCounts.starredByFeedID[secondFeed.id] == 0)
        let requestedFeedIDs: Set<UUID> = [firstFeed.id, secondFeed.id]
        let stateScanObservations = observations.filter { $0.kind == .aggregateStateScan }
        let articleCountObservations = observations.filter { $0.kind == .unreadArticleCount }

        #expect(operations.fetchCountQueryCount == requestedFeedIDs.count + articleCountObservations.count)
        #expect(
            operations.fetchCount - operations.fetchCountQueryCount
                == stateScanObservations.count + requestedFeedIDs.count
        )
        #expect(
            stateScanObservations.allSatisfy {
                $0.feedIDs.count == 1
                    && $0.feedIDs.isSubset(of: requestedFeedIDs)
                    && $0.materializedStateCount <= 2
            }
        )
        #expect(
            articleCountObservations.allSatisfy {
                $0.feedIDs.count == 1
                    && $0.requestedIdentityCount <= 2
                    && $0.materializedStateCount == 0
            }
        )
        for feedID in requestedFeedIDs {
            let feedScans = stateScanObservations.filter { $0.feedIDs == [feedID] }
            #expect(feedScans.first?.appliedKeysetCursor == false)
            #expect(feedScans.dropFirst().allSatisfy { $0.appliedKeysetCursor })
        }
        #expect(observations.contains { $0.kind == .overlay } == false)
    }

    @Test
    func articleStateRepositoryCountsOnlyCanonicalVisibleLinkedStarredArticles() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feeds = try harness.insertFeeds(
            urls: [
                "https://example.com/starred-count-one.xml",
                "https://example.com/starred-count-two.xml"
            ]
        )
        let firstFeed = try #require(feeds.first)
        let secondFeed = try #require(feeds.last)
        let modelContext = harness.modelContainer.mainContext

        for (feed, externalID, archivedAt) in [
            (firstFeed, "visible-starred", nil),
            (firstFeed, "archived-starred", Date.distantPast),
            (firstFeed, "hidden-starred", nil),
            (firstFeed, "newer-unstarred", nil),
            (secondFeed, "second-visible-starred", nil)
        ] {
            _ = try harness.insertArticle(
                feed: feed,
                externalID: externalID,
                url: "https://example.com/\(externalID)",
                title: externalID,
                archivedAt: archivedAt
            )
        }

        modelContext.insert(ArticleState(
            articleExternalID: "visible-starred",
            feedID: firstFeed.id,
            isStarred: true,
            updatedAt: Date(timeIntervalSince1970: 10)
        ))
        modelContext.insert(ArticleState(
            articleExternalID: "archived-starred",
            feedID: firstFeed.id,
            isStarred: true,
            updatedAt: Date(timeIntervalSince1970: 20)
        ))
        modelContext.insert(ArticleState(
            articleExternalID: "hidden-starred",
            feedID: firstFeed.id,
            isStarred: true,
            isHidden: true,
            updatedAt: Date(timeIntervalSince1970: 30)
        ))
        modelContext.insert(ArticleState(
            articleExternalID: "newer-unstarred",
            feedID: firstFeed.id,
            isStarred: true,
            updatedAt: Date(timeIntervalSince1970: 40)
        ))
        modelContext.insert(ArticleState(
            articleExternalID: "newer-unstarred",
            feedID: firstFeed.id,
            isStarred: false,
            updatedAt: Date(timeIntervalSince1970: 50)
        ))
        modelContext.insert(ArticleState(
            articleExternalID: "orphan-starred",
            feedID: firstFeed.id,
            isStarred: true,
            updatedAt: Date(timeIntervalSince1970: 60)
        ))
        modelContext.insert(ArticleState(
            articleExternalID: "second-visible-starred",
            feedID: secondFeed.id,
            isStarred: true,
            updatedAt: Date(timeIntervalSince1970: 70)
        ))
        try modelContext.save()

        let operations = SwiftDataRepositoryOperationCounter()
        var observations: [ArticleStateQueryBatchObservation] = []
        let repository = SwiftDataArticleStateRepository(
            modelContext: modelContext,
            persistenceOperationRecorder: operations.record,
            queryBatchSize: 2,
            queryBatchProbe: { observations.append($0) }
        )

        let aggregateCounts = try repository.fetchAggregateCounts(
            feedIDs: [firstFeed.id, secondFeed.id, firstFeed.id]
        )
        let stateScans = observations.filter { $0.kind == .aggregateStateScan }
        let starredArticleCounts = observations.filter { $0.kind == .starredArticleCount }
        let unreadArticleCounts = observations.filter { $0.kind == .unreadArticleCount }

        #expect(aggregateCounts.unreadByFeedID[firstFeed.id] == 3)
        #expect(aggregateCounts.unreadByFeedID[secondFeed.id] == 1)
        #expect(aggregateCounts.starredByFeedID[firstFeed.id] == 2)
        #expect(aggregateCounts.starredByFeedID[secondFeed.id] == 1)
        #expect(stateScans.allSatisfy { $0.materializedStateCount <= 2 })
        #expect(starredArticleCounts.allSatisfy { $0.requestedIdentityCount <= 2 })
        #expect(starredArticleCounts.reduce(0) { $0 + $1.countedArticleCount } == 3)
        #expect(
            operations.fetchCountQueryCount
                == feeds.count + starredArticleCounts.count + unreadArticleCounts.count
        )
        #expect(operations.fetchCount - operations.fetchCountQueryCount == stateScans.count + feeds.count)
        #expect(observations.contains { $0.kind == .overlay } == false)
    }

    @Test
    func articleStateRepositoryCompatibilityCountQueriesRequestOnlyNeededMetric() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(
            try harness.insertFeeds(urls: ["https://example.com/metric-specific-aggregate.xml"]).first
        )
        let modelContext = harness.modelContainer.mainContext
        for index in 0..<3 {
            _ = try harness.insertArticle(
                feed: feed,
                externalID: "metric-specific-\(index)",
                url: "https://example.com/metric-specific/\(index)",
                title: "Metric Specific \(index)"
            )
            modelContext.insert(
                ArticleState(
                    articleExternalID: "metric-specific-\(index)",
                    feedID: feed.id,
                    isRead: index == 0,
                    isStarred: index == 1,
                    updatedAt: Date(timeIntervalSince1970: TimeInterval(index))
                )
            )
        }
        try modelContext.save()

        var observations: [ArticleStateQueryBatchObservation] = []
        let repository = SwiftDataArticleStateRepository(
            modelContext: modelContext,
            queryBatchSize: 1,
            queryBatchProbe: { observations.append($0) }
        )

        let unreadCounts = try repository.fetchUnreadCounts(feedIDs: [feed.id])

        #expect(unreadCounts[feed.id] == 2)
        #expect(observations.contains { $0.kind == .unreadArticleCount })
        #expect(observations.contains { $0.kind == .starredArticleCount } == false)

        observations.removeAll()
        let starredCounts = try repository.fetchStarredCounts(feedIDs: [feed.id])

        #expect(starredCounts[feed.id] == 1)
        #expect(observations.contains { $0.kind == .starredArticleCount })
        #expect(observations.contains { $0.kind == .unreadArticleCount } == false)
    }

    @Test
    func articleStateRepositoryKeepsUnreadAndStarredAggregatesWithinIndependentBudgets() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let fixture = try ArticleQueryLoadFixture.insert(
            into: harness.modelContainer.mainContext
        )
        let modelContext = harness.modelContainer.mainContext
        let stateCountsByFeedID = try Dictionary(uniqueKeysWithValues: fixture.feedIDs.map { feedID in
            let descriptor = FetchDescriptor<ArticleState>(
                predicate: #Predicate<ArticleState> { state in
                    state.feedID == feedID
                }
            )
            return (feedID, try modelContext.fetchCount(descriptor))
        })
        let stateCount = stateCountsByFeedID.values.reduce(0, +)
        let operations = SwiftDataRepositoryOperationCounter()
        var observations: [ArticleStateQueryBatchObservation] = []
        let repository = SwiftDataArticleStateRepository(
            modelContext: modelContext,
            persistenceOperationRecorder: operations.record,
            queryBatchProbe: { observations.append($0) }
        )
        let expectedCounts = Dictionary(uniqueKeysWithValues: fixture.feedIDs.enumerated().map {
            feedIndex, feedID in
            let lowerBound = feedIndex * ArticleQueryLoadTestContract.articlesPerFeed
            let upperBound = lowerBound + ArticleQueryLoadTestContract.articlesPerFeed
            let readCount = (lowerBound..<upperBound).reduce(into: 0) { count, articleIndex in
                if articleIndex.isMultiple(of: 3) {
                    count += 1
                }
            }
            return (feedID, ArticleQueryLoadTestContract.articlesPerFeed - readCount)
        })
        let expectedStarredCounts = Dictionary(
            uniqueKeysWithValues: fixture.feedIDs.map { ($0, 125) }
        )

        let unreadCounts = try repository.fetchUnreadCounts(feedIDs: fixture.feedIDs)
        let unreadStateScans = observations.filter { $0.kind == .aggregateStateScan }
        let unreadArticleCounts = observations.filter { $0.kind == .unreadArticleCount }
        let unreadBudget = ArticleQueryLoadTestContract.unreadAggregateBudget

        #expect(unreadCounts == expectedCounts)
        #expect(unreadStateScans.reduce(0) { $0 + $1.materializedStateCount } == stateCount)
        #expect(unreadStateScans.count <= unreadBudget.maximumStateScanBatchCount)
        #expect(unreadArticleCounts.isEmpty == false)
        #expect(unreadArticleCounts.count <= unreadBudget.maximumIdentityCountBatchCount)
        #expect(
            unreadStateScans.allSatisfy {
                $0.feedIDs.count == 1
                    && $0.feedIDs.isSubset(of: Set(fixture.feedIDs))
                    && $0.materializedStateCount
                        <= ArticleQueryLoadTestContract.maximumAggregateMaterializedStateBatchSize
            }
        )
        #expect(
            unreadArticleCounts.allSatisfy {
                $0.feedIDs.count == 1
                    && $0.requestedIdentityCount
                        <= ArticleQueryLoadTestContract.maximumAggregateRequestedIdentityBatchSize
                    && $0.materializedStateCount == 0
            }
        )
        #expect(observations.contains { $0.kind == .starredArticleCount } == false)
        #expect(operations.fetchQueryCount <= unreadBudget.maximumFetchQueryCount)
        #expect(operations.fetchQueryCount == unreadStateScans.count + fixture.feedIDs.count)
        #expect(
            operations.fetchCountQueryCount <= unreadBudget.maximumFetchCountQueryCount
        )
        #expect(
            operations.fetchCountQueryCount == fixture.feedIDs.count + unreadArticleCounts.count
        )
        for feedID in fixture.feedIDs {
            let feedScans = unreadStateScans.filter { $0.feedIDs == [feedID] }
            #expect(feedScans.first?.appliedKeysetCursor == false)
            #expect(feedScans.dropFirst().allSatisfy { $0.appliedKeysetCursor })
        }

        operations.reset()
        observations.removeAll()

        let starredCounts = try repository.fetchStarredCounts(feedIDs: fixture.feedIDs)
        let starredStateScans = observations.filter { $0.kind == .aggregateStateScan }
        let starredArticleCounts = observations.filter { $0.kind == .starredArticleCount }
        let starredBudget = ArticleQueryLoadTestContract.starredAggregateBudget

        #expect(starredCounts == expectedStarredCounts)
        #expect(starredStateScans.reduce(0) { $0 + $1.materializedStateCount } == stateCount)
        #expect(starredStateScans.count <= starredBudget.maximumStateScanBatchCount)
        #expect(starredArticleCounts.isEmpty == false)
        #expect(starredArticleCounts.count <= starredBudget.maximumIdentityCountBatchCount)
        #expect(
            starredStateScans.allSatisfy {
                $0.feedIDs.count == 1
                    && $0.feedIDs.isSubset(of: Set(fixture.feedIDs))
                    && $0.materializedStateCount
                        <= ArticleQueryLoadTestContract.maximumAggregateMaterializedStateBatchSize
            }
        )
        #expect(
            starredArticleCounts.allSatisfy {
                $0.feedIDs.count == 1
                    && $0.requestedIdentityCount
                        <= ArticleQueryLoadTestContract.maximumAggregateRequestedIdentityBatchSize
                    && $0.materializedStateCount == 0
            }
        )
        #expect(observations.contains { $0.kind == .unreadArticleCount } == false)
        #expect(operations.fetchQueryCount <= starredBudget.maximumFetchQueryCount)
        #expect(operations.fetchQueryCount == starredStateScans.count + fixture.feedIDs.count)
        #expect(
            operations.fetchCountQueryCount <= starredBudget.maximumFetchCountQueryCount
        )
        #expect(operations.fetchCountQueryCount == starredArticleCounts.count)
        for feedID in fixture.feedIDs {
            let feedScans = starredStateScans.filter { $0.feedIDs == [feedID] }
            #expect(feedScans.first?.appliedKeysetCursor == false)
            #expect(feedScans.dropFirst().allSatisfy { $0.appliedKeysetCursor })
        }
    }

    @Test
    func articleStateRepositoryCancellationDoesNotPublishPartialAggregateCounts() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(
            try harness.insertFeeds(urls: ["https://example.com/cancelled-aggregate.xml"]).first
        )
        for index in 0..<3 {
            _ = try harness.insertArticle(
                feed: feed,
                externalID: "cancelled-aggregate-\(index)",
                url: "https://example.com/cancelled-aggregate/\(index)",
                title: "Cancelled Aggregate \(index)"
            )
            harness.modelContainer.mainContext.insert(
                ArticleState(
                    articleExternalID: "cancelled-aggregate-\(index)",
                    feedID: feed.id,
                    isRead: index == 0,
                    isStarred: index == 1,
                    updatedAt: Date(timeIntervalSince1970: TimeInterval(index))
                )
            )
        }
        try harness.saveModelContext()

        var checkpointCount = 0
        var observations: [ArticleStateQueryBatchObservation] = []
        let cancelledRepository = SwiftDataArticleStateRepository(
            modelContext: harness.modelContainer.mainContext,
            queryBatchSize: 1,
            queryBatchProbe: { observations.append($0) },
            aggregateCancellationCheckpoint: {
                checkpointCount += 1
                if checkpointCount == 4 {
                    throw CancellationError()
                }
            }
        )

        #expect(throws: CancellationError.self) {
            _ = try cancelledRepository.fetchAggregateCounts(feedIDs: [feed.id])
        }
        #expect(observations.filter { $0.kind == .aggregateStateScan }.count == 1)

        let completeCounts = try harness.articleStateRepository.fetchAggregateCounts(
            feedIDs: [feed.id]
        )
        #expect(completeCounts.unreadByFeedID[feed.id] == 2)
        #expect(completeCounts.starredByFeedID[feed.id] == 1)
    }
}
