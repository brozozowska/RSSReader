import Foundation
import SwiftData
import Testing
@testable import RSSReader

@Suite("Article Screen / Starred Consistency")
@MainActor
struct ArticleScreenStarredConsistencyTests {
    @Test(arguments: [false, true])
    func firstTapUsesDisplayedActionWhenPersistedStateChanged(isStarred: Bool) async throws {
        let (harness, article) = try makeArticle()
        _ = try harness.articleStateService.setStarred(
            feedID: article.feedID, articleExternalID: article.externalID,
            isStarred: isStarred, at: .now
        )
        let list = ArticlesScreenController()
        await list.load(selection: .inbox, sidebarArticleFilter: .allItems, dependencies: harness.dependencies)
        let session = reference(for: list)
        let reader = ArticleScreenController()
        await reader.load(articleID: article.id, dependencies: harness.dependencies)
        let originalBody = reader.screenState.article?.contentHTML

        // Simulate sync/swipe changing persistence while the Reader still shows its loaded DTO.
        _ = try harness.articleStateService.setStarred(
            feedID: article.feedID, articleExternalID: article.externalID,
            isStarred: !isStarred, at: .now
        )
        var callbacks = 0
        reader.toggleArticleStarredStatus(
            dependencies: harness.dependencies, isPreviewMode: false,
            articleStateMutationHandler: { id, state in
                callbacks += 1
                #expect(list.applyArticleStateMutation(articleID: id, persistedState: state, in: session))
            }
        )

        #expect(callbacks == 1)
        #expect(reader.screenState.article?.isStarred == !isStarred)
        #expect(reader.screenState.article?.contentHTML == originalBody)
        #expect(reader.screenState.phase == .loaded)
        #expect(reader.screenState.toolbarActions.bottomActions?.starSystemImage == (!isStarred ? "star.slash" : "star"))
        #expect(list.screenState.articles.first?.isStarred == !isStarred)
        let persisted = try harness.articleStateRepository.fetchStateSnapshot(
            feedID: article.feedID, articleExternalID: article.externalID
        )
        #expect(persisted?.isStarred == !isStarred)

        let starred = ArticlesScreenController()
        await starred.load(selection: .starred, sidebarArticleFilter: .allItems, dependencies: harness.dependencies)
        #expect(starred.visibleArticleIDs() == (!isStarred ? [article.id] : []))
    }

    @Test
    func rapidTogglesKeepReaderAndRetainedStarredSessionConsistentOnReturn() async throws {
        let (harness, article) = try makeArticle()
        _ = try harness.articleStateService.setStarred(
            feedID: article.feedID, articleExternalID: article.externalID, isStarred: true, at: .now
        )
        let list = ArticlesScreenController()
        await list.load(
            selection: .starred, sidebarArticleFilter: .allItems,
            dependencies: harness.dependencies, refreshesScopeMetric: true
        )
        let session = reference(for: list)
        let reader = ArticleScreenController()
        await reader.load(articleID: article.id, dependencies: harness.dependencies)
        var callbacks = 0

        // No await/render turn between taps: each action must use the just-resolved Reader state.
        for index in 0..<7 {
            reader.toggleArticleStarredStatus(
                dependencies: harness.dependencies, isPreviewMode: false,
                articleStateMutationHandler: { id, state in
                    callbacks += 1
                    #expect(list.applyArticleStateMutation(articleID: id, persistedState: state, in: session))
                }
            )
            let expected = index % 2 == 1
            #expect(reader.screenState.article?.isStarred == expected)
            #expect(list.screenState.articles.first?.isStarred == expected)
            #expect(list.screenState.articleListSession.scopeMetric == ArticleScopeMetric(kind: .starred, count: expected ? 1 : 0))
        }
        #expect(callbacks == 7)
        #expect(list.currentArticleListSessionID == session.id)
        #expect(list.visibleArticleIDs() == [article.id])
        #expect(list.screenState.articleListSession.entries.first?.membershipStatus == .retainedAfterFilterMutation)

        await list.load(
            selection: .starred, sidebarArticleFilter: .allItems,
            dependencies: harness.dependencies, retainsSessionFilterMutations: true,
            preservesMaterializedSessionSnapshot: true
        )
        #expect(list.currentArticleListSessionID == session.id)
        #expect(list.screenState.articles.first?.isStarred == false)
        #expect(list.screenState.navigationSubtitle == ReadingLocalization.starredItemsSubtitle(count: 0))
        await list.load(selection: .starred, sidebarArticleFilter: .allItems, dependencies: harness.dependencies)
        #expect(list.visibleArticleIDs().isEmpty)
        #expect(list.currentArticleListSessionID != session.id)
    }

    @Test
    func rejectedLWWUpdatePublishesPersistedStateWithoutFalseRetention() async throws {
        let (harness, article) = try makeArticle()
        _ = try harness.articleStateService.setStarred(
            feedID: article.feedID, articleExternalID: article.externalID,
            isStarred: true, at: .distantFuture
        )
        let list = ArticlesScreenController()
        await list.load(
            selection: .starred, sidebarArticleFilter: .allItems,
            dependencies: harness.dependencies, refreshesScopeMetric: true
        )
        let session = reference(for: list)
        let reader = ArticleScreenController()
        await reader.load(articleID: article.id, dependencies: harness.dependencies)
        reader.toggleArticleStarredStatus(
            dependencies: harness.dependencies, isPreviewMode: false,
            articleStateMutationHandler: { id, state in
                #expect(list.applyArticleStateMutation(articleID: id, persistedState: state, in: session))
            }
        )
        #expect(reader.screenState.article?.isStarred == true)
        #expect(list.screenState.articles.first?.isStarred == true)
        #expect(list.screenState.articleListSession.scopeMetric == ArticleScopeMetric(kind: .starred, count: 1))
        #expect(list.screenState.articleListSession.entries.first?.membershipStatus != .retainedAfterFilterMutation)
    }

    @Test(arguments: [Optional<Bool>.none, false, true])
    func saveFailureRestoresStateAndDoesNotPublishMutation(initialStarred: Bool?) async throws {
        let (harness, article) = try makeArticle()
        harness.modelContainer.mainContext.autosaveEnabled = false
        if let initialStarred {
            _ = try harness.articleStateService.setStarred(
                feedID: article.feedID, articleExternalID: article.externalID,
                isStarred: initialStarred, at: .now
            )
        }
        var failsSave = true
        let repository = SwiftDataArticleStateRepository(
            modelContext: harness.modelContainer.mainContext,
            persistenceSaveOperation: { context in
                if failsSave { throw InjectedSaveFailure() }
                try context.save()
            }
        )
        let service = ArticleStateService(logger: TestLogger(), articleStateRepository: repository)
        let reader = ArticleScreenController(articleStateService: service)
        await reader.load(articleID: article.id, dependencies: harness.dependencies)
        let previous = try repository.fetchStateSnapshot(feedID: article.feedID, articleExternalID: article.externalID)
        let previousToolbar = reader.screenState.toolbarActions
        article.title = "Unrelated pending title"
        var callbacks = 0
        reader.toggleArticleStarredStatus(
            dependencies: harness.dependencies, isPreviewMode: false,
            articleStateMutationHandler: { _, _ in callbacks += 1 }
        )
        #expect(callbacks == 0)
        #expect(reader.screenState.article?.isStarred == (initialStarred ?? false))
        #expect(reader.screenState.toolbarActions == previousToolbar)
        #expect(article.title == "Unrelated pending title")
        let restored = try repository.fetchStateSnapshot(feedID: article.feedID, articleExternalID: article.externalID)
        #expect(restored?.isStarred == previous?.isStarred)
        #expect(restored?.updatedAt == previous?.updatedAt)
        #expect(restored?.readAt == previous?.readAt)

        failsSave = false
        reader.toggleArticleStarredStatus(
            dependencies: harness.dependencies, isPreviewMode: false,
            articleStateMutationHandler: { _, _ in callbacks += 1 }
        )
        #expect(callbacks == 1)
        #expect(reader.screenState.article?.isStarred == !(initialStarred ?? false))
        let savedRepository = SwiftDataArticleStateRepository(modelContext: ModelContext(harness.modelContainer))
        let saved = try savedRepository.fetchStateSnapshot(feedID: article.feedID, articleExternalID: article.externalID)
        #expect(saved?.isStarred == !(initialStarred ?? false))
        #expect(article.title == "Unrelated pending title")
    }

    @Test
    func mutationFromEndedSessionCannotUpdateNewSession() async throws {
        let (harness, article) = try makeArticle()
        let list = ArticlesScreenController()
        await list.load(selection: .inbox, sidebarArticleFilter: .allItems, dependencies: harness.dependencies)
        let oldSession = reference(for: list)
        list.endPresentation()
        await list.load(selection: .inbox, sidebarArticleFilter: .allItems, dependencies: harness.dependencies)
        let state = try harness.articleStateService.setStarred(
            feedID: article.feedID, articleExternalID: article.externalID, isStarred: true, at: .now
        )
        #expect(!list.applyArticleStateMutation(articleID: article.id, persistedState: state, in: oldSession))
        #expect(list.screenState.articles.first?.isStarred == false)
    }

    private func reference(for list: ArticlesScreenController) -> ArticleListSessionReference {
        ArticleListSessionReference(
            id: list.currentArticleListSessionID,
            sidebarSelection: list.screenState.articleListSession.context.selection,
            sidebarArticleFilter: list.screenState.articleListSession.context.sidebarArticleFilter
        )
    }

    private func makeArticle() throws -> (TestHarness, Article) {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/star-consistency.xml"]).first)
        let article = try harness.insertArticle(
            feed: feed, externalID: "star-consistency",
            url: "https://example.com/article", title: "Star Consistency"
        )
        return (harness, article)
    }

    private struct InjectedSaveFailure: Error {}
}
