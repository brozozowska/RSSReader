import Foundation
import Testing
@testable import RSSReader

@Suite("Article Screen / Controller")
@MainActor
struct ArticleScreenControllerTests {
    @Test
    func articleScreenControllerLoadsReaderArticleForCurrentSelection() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/article-screen-load.xml"]).first)
        let article = try harness.insertArticle(
            feed: feed,
            externalID: "article-screen-load",
            url: "https://example.com/articles/article-screen-load",
            title: "Article Screen Load"
        )
        let controller = ArticleScreenController()

        await controller.load(articleID: article.id, dependencies: harness.dependencies)

        #expect(controller.screenState.phase == .loaded)
        #expect(controller.screenState.derivedViewState().content?.header.title == "Article Screen Load")
        #expect(controller.screenState.toolbarActions.showsBottomActions)
    }

    @Test
    func articleScreenControllerLoadsArchivedReaderArticleWithArchiveMetadata() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/article-screen-archive.xml"]).first)
        let archivedAt = try #require(Calendar.current.date(from: DateComponents(year: 2024, month: 1, day: 1)))
        let article = try harness.insertArticle(
            feed: feed,
            externalID: "article-screen-archive",
            url: "https://example.com/articles/article-screen-archive",
            title: "Article Screen Archive",
            archivedAt: archivedAt
        )
        let controller = ArticleScreenController()

        await controller.load(articleID: article.id, dependencies: harness.dependencies)

        #expect(controller.screenState.phase == .loaded)
        #expect(controller.screenState.article?.title == "Article Screen Archive")
        #expect(controller.screenState.article?.archivedAt == archivedAt)
    }

    @Test
    func articleScreenControllerMarksArticleAsReadOnOpenWhenSettingIsEnabled() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appSettingsRepository = try #require(harness.dependencies.appSettingsRepository)
        _ = try appSettingsRepository.update(
            AppSettingsUpdate(
                markAsReadOnOpen: true,
                updatedAt: .distantPast
            )
        )
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/article-screen-mark-on-open.xml"]).first)
        let article = try harness.insertArticle(
            feed: feed,
            externalID: "article-screen-mark-on-open",
            url: "https://example.com/articles/article-screen-mark-on-open",
            title: "Article Screen Mark On Open"
        )
        let controller = ArticleScreenController()
        var recordedReadArticleIDs: [UUID] = []

        await controller.load(
            articleID: article.id,
            dependencies: harness.dependencies,
            articleReadOnOpenHandler: { articleID, _ in recordedReadArticleIDs.append(articleID) }
        )

        let loadedArticle = try #require(controller.screenState.article)
        #expect(loadedArticle.isRead == true)
        #expect(recordedReadArticleIDs == [article.id])
        #expect(controller.screenState.toolbarActions.bottomActions?.readToggleTitle == ReadingLocalization.markUnreadAction)
        #expect(controller.screenState.toolbarActions.bottomActions?.readToggleSystemImage == "circle.slash")

        let persistedState = try harness.articleStateRepository.fetchStateSnapshot(
            feedID: feed.id,
            articleExternalID: article.externalID
        )
        #expect(persistedState?.isRead == true)
    }

    @Test
    func articleScreenControllerKeepsArticleUnreadOnOpenWhenSettingIsDisabled() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appSettingsRepository = try #require(harness.dependencies.appSettingsRepository)
        _ = try appSettingsRepository.update(
            AppSettingsUpdate(
                markAsReadOnOpen: false,
                updatedAt: .distantPast
            )
        )
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/article-screen-keep-unread-on-open.xml"]).first)
        let article = try harness.insertArticle(
            feed: feed,
            externalID: "article-screen-keep-unread-on-open",
            url: "https://example.com/articles/article-screen-keep-unread-on-open",
            title: "Article Screen Keep Unread On Open"
        )
        let controller = ArticleScreenController()
        var recordedReadArticleIDs: [UUID] = []

        await controller.load(
            articleID: article.id,
            dependencies: harness.dependencies,
            articleReadOnOpenHandler: { articleID, _ in recordedReadArticleIDs.append(articleID) }
        )

        let loadedArticle = try #require(controller.screenState.article)
        #expect(loadedArticle.isRead == false)
        #expect(recordedReadArticleIDs.isEmpty)
        #expect(controller.screenState.toolbarActions.bottomActions?.readToggleTitle == ReadingLocalization.markReadAction)
        #expect(controller.screenState.toolbarActions.bottomActions?.readToggleSystemImage == "circle")

        let persistedState = try harness.articleStateRepository.fetchStateSnapshot(
            feedID: feed.id,
            articleExternalID: article.externalID
        )
        #expect(persistedState == nil)
    }

    @Test
    func articleScreenControllerUsesPersistedReadStateWhenMarkOnOpenLosesLWWConflict() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(
            try harness.insertFeeds(urls: ["https://example.com/article-screen-mark-on-open-lww.xml"]).first
        )
        let article = try harness.insertArticle(
            feed: feed,
            externalID: "article-screen-mark-on-open-lww",
            url: "https://example.com/articles/article-screen-mark-on-open-lww",
            title: "Article Screen Mark On Open LWW"
        )
        _ = try harness.articleStateService.markAsUnread(
            feedID: feed.id,
            articleExternalID: article.externalID,
            at: .distantFuture
        )
        let controller = ArticleScreenController()
        var publishedReadStates: [Bool] = []

        await controller.load(
            articleID: article.id,
            dependencies: harness.dependencies,
            articleReadOnOpenHandler: { _, persistedState in
                publishedReadStates.append(persistedState.isRead)
            }
        )

        #expect(controller.screenState.article?.isRead == false)
        #expect(publishedReadStates == [false])
        #expect(
            try harness.articleStateRepository.fetchStateSnapshot(
                feedID: feed.id,
                articleExternalID: article.externalID
            )?.isRead == false
        )
    }

    @Test
    func articleScreenControllerBuildsNotFoundPlaceholderWhenArticleDoesNotExist() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let controller = ArticleScreenController()

        await controller.load(articleID: UUID(), dependencies: harness.dependencies)

        #expect(controller.screenState.phase == .notFound)
        #expect(controller.screenState.placeholder?.title == ReadingLocalization.articleNotFoundTitle)
    }

    @Test
    func articleScreenControllerBuildsFailedPlaceholderWhenArticleQueryServiceIsUnavailable() async {
        let dependencies = AppDependencies(logger: TestLogger())
        let controller = ArticleScreenController()

        await controller.load(articleID: UUID(), dependencies: dependencies)

        #expect(controller.screenState.phase == .failed(ReadingLocalization.articleQueryUnavailableMessage))
        #expect(controller.screenState.placeholder?.title == ReadingLocalization.failedToLoadArticleTitle)
        #expect(
            controller.screenState.placeholder?.description
                == ReadingLocalization.articleQueryUnavailableMessage
        )
    }

    @Test
    func articleScreenControllerTogglesArticleReadStatusWithoutReloadingScreen() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/article-screen-mark-unread.xml"]).first)
        let article = try harness.insertArticle(
            feed: feed,
            externalID: "article-screen-mark-unread",
            url: "https://example.com/articles/article-screen-mark-unread",
            title: "Article Screen Mark Unread"
        )
        _ = try harness.articleStateService.markAsRead(
            feedID: feed.id,
            articleExternalID: article.externalID,
            at: .now
        )
        let controller = ArticleScreenController()

        await controller.load(articleID: article.id, dependencies: harness.dependencies)
        controller.toggleArticleReadStatus(
            dependencies: harness.dependencies,
            isPreviewMode: false
        )

        var updatedArticle = try #require(controller.screenState.article)
        #expect(updatedArticle.isRead == false)
        #expect(controller.screenState.phase == .loaded)
        #expect(controller.screenState.toolbarActions.bottomActions?.readToggleTitle == ReadingLocalization.markReadAction)
        #expect(controller.screenState.toolbarActions.bottomActions?.readToggleSystemImage == "circle")

        var persistedState = try harness.articleStateRepository.fetchStateSnapshot(
            feedID: feed.id,
            articleExternalID: article.externalID
        )
        #expect(persistedState?.isRead == false)

        controller.toggleArticleReadStatus(
            dependencies: harness.dependencies,
            isPreviewMode: false
        )

        updatedArticle = try #require(controller.screenState.article)
        #expect(updatedArticle.isRead == true)
        #expect(controller.screenState.toolbarActions.bottomActions?.readToggleTitle == ReadingLocalization.markUnreadAction)
        #expect(controller.screenState.toolbarActions.bottomActions?.readToggleSystemImage == "circle.slash")

        persistedState = try harness.articleStateRepository.fetchStateSnapshot(
            feedID: feed.id,
            articleExternalID: article.externalID
        )
        #expect(persistedState?.isRead == true)
    }

    @Test
    func articleScreenControllerTogglesArticleStarredStatusWithoutReloadingScreen() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/article-screen-toggle-star.xml"]).first)
        let article = try harness.insertArticle(
            feed: feed,
            externalID: "article-screen-toggle-star",
            url: "https://example.com/articles/article-screen-toggle-star",
            title: "Article Screen Toggle Star"
        )
        let controller = ArticleScreenController()

        await controller.load(articleID: article.id, dependencies: harness.dependencies)
        controller.toggleArticleStarredStatus(
            dependencies: harness.dependencies,
            isPreviewMode: false
        )

        var updatedArticle = try #require(controller.screenState.article)
        #expect(updatedArticle.isStarred == true)
        #expect(controller.screenState.phase == .loaded)
        #expect(controller.screenState.toolbarActions.bottomActions?.starTitle == ReadingLocalization.unstarAction)
        #expect(controller.screenState.toolbarActions.bottomActions?.starSystemImage == "star.slash")

        var persistedState = try harness.articleStateRepository.fetchStateSnapshot(
            feedID: feed.id,
            articleExternalID: article.externalID
        )
        #expect(persistedState?.isStarred == true)

        controller.toggleArticleStarredStatus(
            dependencies: harness.dependencies,
            isPreviewMode: false
        )

        updatedArticle = try #require(controller.screenState.article)
        #expect(updatedArticle.isStarred == false)
        #expect(controller.screenState.toolbarActions.bottomActions?.starTitle == ReadingLocalization.starAction)
        #expect(controller.screenState.toolbarActions.bottomActions?.starSystemImage == "star")

        persistedState = try harness.articleStateRepository.fetchStateSnapshot(
            feedID: feed.id,
            articleExternalID: article.externalID
        )
        #expect(persistedState?.isStarred == false)
    }

    @Test
    func articleScreenControllerOpensCurrentArticleInAppLevelSafariRoute() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appState = AppState()
        let appSettingsRepository = try #require(harness.dependencies.appSettingsRepository)
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/article-screen-open-web.xml"]).first)
        let articleModel = try harness.insertArticle(
            feed: feed,
            externalID: "article-screen-open-web",
            url: "https://example.com/articles/article-screen-open-web",
            title: "Article Screen Open Web"
        )
        _ = try appSettingsRepository.update(
            AppSettingsUpdate(
                articleSourceLinkOpeningPolicy: .inAppBrowser,
                updatedAt: .distantPast
            )
        )
        articleModel.canonicalURL = "https://example.com/articles/article-screen-open-web/canonical"
        try harness.saveModelContext()
        let controller = ArticleScreenController()
        var externallyOpenedURL: URL?

        await controller.load(articleID: articleModel.id, dependencies: harness.dependencies)
        controller.openSourceArticle(
            dependencies: harness.dependencies,
            appState: appState,
            openExternalURL: { url in
                externallyOpenedURL = url
            }
        )

        #expect(
            appState.selectedDetailRoute == .safari(
                ArticleSafariRoute(
                    articleID: articleModel.id,
                    url: URL(string: "https://example.com/articles/article-screen-open-web/canonical")!
                ),
                dismissalTarget: .article
            )
        )
        #expect(
            appState.presentedSafariRoute == ArticleSafariRoute(
                articleID: articleModel.id,
                url: URL(string: "https://example.com/articles/article-screen-open-web/canonical")!
            )
        )
        #expect(externallyOpenedURL == nil)
    }

    @Test
    func articleScreenControllerOpensCurrentArticleInExternalBrowserWhenSourcePolicyRequiresIt() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appState = AppState()
        let appSettingsRepository = try #require(harness.dependencies.appSettingsRepository)
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/article-screen-open-external.xml"]).first)
        let articleModel = try harness.insertArticle(
            feed: feed,
            externalID: "article-screen-open-external",
            url: "https://example.com/articles/article-screen-open-external",
            title: "Article Screen Open External"
        )
        _ = try appSettingsRepository.update(
            AppSettingsUpdate(
                articleSourceLinkOpeningPolicy: .externalBrowser,
                updatedAt: .distantPast
            )
        )
        articleModel.canonicalURL = "https://example.com/articles/article-screen-open-external/canonical"
        try harness.saveModelContext()
        let controller = ArticleScreenController()
        var externallyOpenedURL: URL?

        await controller.load(articleID: articleModel.id, dependencies: harness.dependencies)
        controller.openSourceArticle(
            dependencies: harness.dependencies,
            appState: appState,
            openExternalURL: { url in
                externallyOpenedURL = url
            }
        )

        #expect(externallyOpenedURL == URL(string: "https://example.com/articles/article-screen-open-external/canonical")!)
        #expect(appState.selectedDetailRoute == .none)
        #expect(appState.presentedSafariRoute == nil)
    }

    @Test
    func articleScreenControllerHandlesTappedBodyLinkThroughAppLevelSafariRoute() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appState = AppState()
        let appSettingsRepository = try #require(harness.dependencies.appSettingsRepository)
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/article-screen-body-link.xml"]).first)
        let articleModel = try harness.insertArticle(
            feed: feed,
            externalID: "article-screen-body-link",
            url: "https://example.com/articles/article-screen-body-link",
            title: "Article Screen Body Link"
        )
        _ = try appSettingsRepository.update(
            AppSettingsUpdate(
                articleBodyLinkOpeningPolicy: .inAppBrowser,
                updatedAt: .distantPast
            )
        )
        try harness.saveModelContext()
        let controller = ArticleScreenController()
        let tappedURL = URL(string: "https://example.com/guides/swift")!
        var externallyOpenedURL: URL?

        await controller.load(articleID: articleModel.id, dependencies: harness.dependencies)
        controller.handleBodyLinkTap(
            tappedURL,
            dependencies: harness.dependencies,
            appState: appState,
            openExternalURL: { url in
                externallyOpenedURL = url
            }
        )

        #expect(
            appState.selectedDetailRoute == .safari(
                ArticleSafariRoute(
                    articleID: articleModel.id,
                    url: tappedURL
                ),
                dismissalTarget: .article
            )
        )
        #expect(
            appState.presentedSafariRoute == ArticleSafariRoute(
                articleID: articleModel.id,
                url: tappedURL
            )
        )
        #expect(externallyOpenedURL == nil)
    }

    @Test
    func articleScreenControllerOpensTappedBodyLinkInExternalBrowserWhenPolicyRequiresIt() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appState = AppState()
        let appSettingsRepository = try #require(harness.dependencies.appSettingsRepository)
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/article-screen-external-body-link.xml"]).first)
        let articleModel = try harness.insertArticle(
            feed: feed,
            externalID: "article-screen-external-body-link",
            url: "https://example.com/articles/article-screen-external-body-link",
            title: "Article Screen External Body Link"
        )
        _ = try appSettingsRepository.update(
            AppSettingsUpdate(
                articleBodyLinkOpeningPolicy: .externalBrowser,
                updatedAt: .distantPast
            )
        )
        try harness.saveModelContext()
        let controller = ArticleScreenController()
        let tappedURL = URL(string: "https://example.com/guides/external")!
        var externallyOpenedURL: URL?

        await controller.load(articleID: articleModel.id, dependencies: harness.dependencies)
        controller.handleBodyLinkTap(
            tappedURL,
            dependencies: harness.dependencies,
            appState: appState,
            openExternalURL: { url in
                externallyOpenedURL = url
            }
        )

        #expect(externallyOpenedURL == tappedURL)
        #expect(appState.selectedDetailRoute == .none)
        #expect(appState.presentedSafariRoute == nil)
    }
}
