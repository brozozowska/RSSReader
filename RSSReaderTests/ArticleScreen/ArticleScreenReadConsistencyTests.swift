import Foundation
import SwiftData
import Testing
@testable import RSSReader

@Suite("Article Screen / Read Consistency")
@MainActor
struct ArticleScreenReadConsistencyTests {
    @Test(arguments: [false, true])
    func readToggleUpdatesUnreadSessionBeforeAndAfterReturn(markAsReadOnOpen: Bool) async throws {
        let (harness, article) = try makeArticle(markAsReadOnOpen: markAsReadOnOpen)
        let list = ArticlesScreenController()
        await list.load(selection: .unread, sidebarArticleFilter: .allItems,
            dependencies: harness.dependencies, refreshesScopeMetric: true)
        let session = reference(for: list)
        let callback: ArticleStateMutationHandler = { id, state in
            #expect(list.applyArticleStateMutation(articleID: id, persistedState: state, in: session))
        }
        let reader = ArticleScreenController()
        await reader.load(articleID: article.id, dependencies: harness.dependencies,
            articleReadOnOpenHandler: callback)
        #expect(reader.screenState.article?.isRead == markAsReadOnOpen)
        #expect(list.screenState.articles.first?.isRead == markAsReadOnOpen)
        #expect(list.screenState.articleListSession.scopeMetric == ArticleScopeMetric(kind: .unread, count: markAsReadOnOpen ? 0 : 1))

        reader.toggleArticleReadStatus(dependencies: harness.dependencies, isPreviewMode: false,
            articleStateMutationHandler: callback)
        let expectedIsRead = !markAsReadOnOpen
        #expect(reader.screenState.article?.isRead == expectedIsRead)
        #expect(list.screenState.articles.first?.isRead == expectedIsRead)
        #expect(list.screenState.articleListSession.scopeMetric == ArticleScopeMetric(kind: .unread, count: expectedIsRead ? 0 : 1))
        #expect(reader.screenState.toolbarActions.bottomActions?.readToggleSystemImage == (expectedIsRead ? "circle.slash" : "circle"))
        #expect(list.visibleArticleIDs() == [article.id])

        await list.load(selection: .unread, sidebarArticleFilter: .allItems,
            dependencies: harness.dependencies, refreshesScopeMetric: false,
            retainsSessionFilterMutations: true, preservesMaterializedSessionSnapshot: true)
        #expect(list.currentArticleListSessionID == session.id)
        #expect(list.screenState.articles.first?.isRead == expectedIsRead)
        #expect(list.screenState.articleListSession.scopeMetric == ArticleScopeMetric(kind: .unread, count: expectedIsRead ? 0 : 1))
        #expect(list.visibleArticleIDs() == [article.id])

        await list.load(selection: .unread, sidebarArticleFilter: .allItems,
            dependencies: harness.dependencies, refreshesScopeMetric: true)
        #expect(list.visibleArticleIDs() == (expectedIsRead ? [] : [article.id]))
    }

    @Test(arguments: [false, true])
    func rapidReadTogglesPublishEachPersistedState(initialIsRead: Bool) async throws {
        let (harness, article) = try makeArticle(markAsReadOnOpen: false)
        _ = try setRead(initialIsRead, article: article, service: harness.articleStateService)
        let list = ArticlesScreenController()
        await list.load(selection: .inbox, sidebarArticleFilter: .allItems, dependencies: harness.dependencies)
        let session = reference(for: list)
        let reader = ArticleScreenController()
        await reader.load(articleID: article.id, dependencies: harness.dependencies)
        var callbacks = 0
        for index in 0..<8 {
            reader.toggleArticleReadStatus(dependencies: harness.dependencies, isPreviewMode: false,
                articleStateMutationHandler: { id, state in
                    callbacks += 1
                    #expect(list.applyArticleStateMutation(articleID: id, persistedState: state, in: session))
                })
            let expected = index % 2 == 0 ? !initialIsRead : initialIsRead
            let persisted = try harness.articleStateRepository.fetchStateSnapshot(
                feedID: article.feedID, articleExternalID: article.externalID)
            #expect(persisted?.isRead == expected)
            #expect(reader.screenState.article?.isRead == expected)
            #expect(list.screenState.articles.first?.isRead == expected)
        }
        #expect(callbacks == 8)
    }

    @Test
    func repeatedReadOnOpenEventCannotOverwriteLaterManualUnread() async throws {
        let (harness, article) = try makeArticle(markAsReadOnOpen: false)
        let list = ArticlesScreenController()
        await list.load(selection: .unread, sidebarArticleFilter: .allItems,
            dependencies: harness.dependencies, refreshesScopeMetric: true)
        let session = reference(for: list)
        let state = try setRead(true, article: article, service: harness.articleStateService)
        let event = ArticleReadOnOpenEvent(articleID: article.id,
            articleListSessionID: session.id, sidebarSelection: .unread,
            sidebarArticleFilter: .allItems, isRead: state.isRead)
        #expect(list.applyArticleReadOnOpenEvent(event))
        let reader = ArticleScreenController()
        await reader.load(articleID: article.id, dependencies: harness.dependencies)
        reader.toggleArticleReadStatus(dependencies: harness.dependencies, isPreviewMode: false,
            articleStateMutationHandler: { id, state in
                #expect(list.applyArticleStateMutation(articleID: id, persistedState: state, in: session))
            })
        #expect(!list.applyArticleReadOnOpenEvent(event))
        #expect(list.screenState.articles.first?.isRead == false)
        #expect(list.screenState.articleListSession.scopeMetric == ArticleScopeMetric(kind: .unread, count: 1))
    }

    @Test(arguments: [false, true])
    func rejectedReadToggleUsesLWWState(initialIsRead: Bool) async throws {
        let (harness, article) = try makeArticle(markAsReadOnOpen: false)
        _ = try setRead(initialIsRead, article: article, service: harness.articleStateService, at: .distantFuture)
        let list = ArticlesScreenController()
        await list.load(selection: .inbox, sidebarArticleFilter: .allItems, dependencies: harness.dependencies)
        let session = reference(for: list)
        let reader = ArticleScreenController()
        await reader.load(articleID: article.id, dependencies: harness.dependencies)
        reader.toggleArticleReadStatus(dependencies: harness.dependencies, isPreviewMode: false,
            articleStateMutationHandler: { id, state in
                #expect(list.applyArticleStateMutation(articleID: id, persistedState: state, in: session))
            })
        #expect(reader.screenState.article?.isRead == initialIsRead)
        #expect(list.screenState.articles.first?.isRead == initialIsRead)
    }

    @Test(arguments: [false, true])
    func saveFailureKeepsReaderListAndPersistenceUnchanged(initialIsRead: Bool) async throws {
        let (harness, article) = try makeArticle(markAsReadOnOpen: false)
        _ = try setRead(initialIsRead, article: article, service: harness.articleStateService)
        harness.modelContainer.mainContext.autosaveEnabled = false
        let list = ArticlesScreenController()
        await list.load(selection: .inbox, sidebarArticleFilter: .allItems, dependencies: harness.dependencies)
        var failsSave = true
        let repository = SwiftDataArticleStateRepository(modelContext: harness.modelContainer.mainContext,
            persistenceSaveOperation: { context in
                if failsSave { throw SaveFailure() }
                try context.save()
            })
        let reader = ArticleScreenController(articleStateService: ArticleStateService(
            logger: TestLogger(), articleStateRepository: repository))
        await reader.load(articleID: article.id, dependencies: harness.dependencies)
        let session = reference(for: list)
        var callbacks = 0
        let callback: ArticleStateMutationHandler = { id, state in
            callbacks += 1
            #expect(list.applyArticleStateMutation(articleID: id, persistedState: state, in: session))
        }
        reader.toggleArticleReadStatus(dependencies: harness.dependencies, isPreviewMode: false,
            articleStateMutationHandler: callback)
        #expect(callbacks == 0)
        #expect(reader.screenState.article?.isRead == initialIsRead)
        #expect(list.screenState.articles.first?.isRead == initialIsRead)
        #expect(try repository.fetchStateSnapshot(feedID: article.feedID,
            articleExternalID: article.externalID)?.isRead == initialIsRead)
        failsSave = false
        reader.toggleArticleReadStatus(dependencies: harness.dependencies, isPreviewMode: false,
            articleStateMutationHandler: callback)
        #expect(callbacks == 1)
        #expect(reader.screenState.article?.isRead == !initialIsRead)
        #expect(list.screenState.articles.first?.isRead == !initialIsRead)
    }

    private func reference(for list: ArticlesScreenController) -> ArticleListSessionReference {
        ArticleListSessionReference(id: list.currentArticleListSessionID,
            sidebarSelection: list.screenState.articleListSession.context.selection,
            sidebarArticleFilter: list.screenState.articleListSession.context.sidebarArticleFilter)
    }

    private func setRead(_ isRead: Bool, article: Article, service: ArticleStateService,
                         at: Date = .now) throws -> ArticleUserStateSnapshot {
        if isRead { return try service.markAsRead(article: article, at: at) }
        return try service.markAsUnread(article: article, at: at)
    }

    private func makeArticle(markAsReadOnOpen: Bool) throws -> (TestHarness, Article) {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        _ = try #require(harness.dependencies.appSettingsRepository).update(
            AppSettingsUpdate(markAsReadOnOpen: markAsReadOnOpen, updatedAt: .distantPast))
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/read-consistency.xml"]).first)
        let article = try harness.insertArticle(feed: feed, externalID: "read-consistency",
            url: "https://example.com/article", title: "Read Consistency")
        return (harness, article)
    }

    private struct SaveFailure: Error {}
}
