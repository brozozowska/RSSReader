import Foundation
import Testing
@testable import RSSReader

@Suite("Shell / Reader Opening And Safari Routing")
@MainActor
struct ReaderOpeningAndSafariRoutingTests {
    @Test
    func readerOpeningModeFeedReaderSelectsAppOwnedReaderWithoutPresentingSafari() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appState = AppState()
        let article = try insertArticle(
            into: harness,
            feedURL: "https://example.com/feed-reader-mode.xml",
            externalID: "feed-reader-mode",
            articleURL: "https://example.com/articles/feed-reader-mode",
            canonicalURL: "https://example.com/articles/feed-reader-mode/canonical"
        )
        try harness.dependencies.appSettingsRepository?.update(
            AppSettingsUpdate(articleOpeningMode: .feedReader)
        )

        harness.dependencies.appActions.selectArticle(id: article.id, using: appState)

        #expect(appState.selectedArticleID == article.id)
        #expect(appState.selectedDetailRoute == .article(article.id))
        #expect(appState.presentedSafariRoute == nil)
    }

    @Test
    func readerOpeningModeSafariViewPresentsSafariAndDismissalRestoresArticleList() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appState = AppState()
        let article = try insertArticle(
            into: harness,
            feedURL: "https://example.com/safari-mode.xml",
            externalID: "safari-mode",
            articleURL: "https://example.com/articles/safari-mode",
            canonicalURL: "https://example.com/articles/safari-mode/canonical"
        )
        let safariURL = URL(string: "https://example.com/articles/safari-mode/canonical")!
        try harness.dependencies.appSettingsRepository?.update(
            AppSettingsUpdate(articleOpeningMode: .safariView)
        )

        harness.dependencies.appActions.selectArticle(id: article.id, using: appState)

        #expect(appState.selectedArticleID == nil)
        #expect(
            appState.selectedDetailRoute == .safari(
                ArticleSafariRoute(articleID: article.id, url: safariURL),
                dismissalTarget: .articleList
            )
        )
        #expect(appState.presentedSafariRoute == ArticleSafariRoute(articleID: article.id, url: safariURL))

        harness.dependencies.appActions.closePresentedArticleSafari(using: appState)

        #expect(appState.selectedArticleID == nil)
        #expect(appState.selectedDetailRoute == .none)
        #expect(appState.presentedSafariRoute == nil)
    }

    @Test
    func readerOpeningModeSafariViewMarksArticleAsReadAndPublishesCurrentListSessionEvent() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appState = AppState()
        let article = try insertArticle(
            into: harness,
            feedURL: "https://example.com/safari-read-on-open.xml",
            externalID: "safari-read-on-open",
            articleURL: "https://example.com/articles/safari-read-on-open"
        )
        try harness.dependencies.appSettingsRepository?.update(
            AppSettingsUpdate(
                articleOpeningMode: .safariView,
                markAsReadOnOpen: true
            )
        )
        appState.selectSidebarSelection(.feed(article.feedID))
        appState.selectSidebarArticleFilter(.unread)

        harness.dependencies.appActions.selectArticle(id: article.id, using: appState)

        let persistedState = try harness.articleStateRepository.fetchStateSnapshot(
            feedID: article.feedID,
            articleExternalID: article.externalID
        )
        #expect(persistedState?.isRead == true)
        #expect(appState.articleReadOnOpenEvent?.articleID == article.id)
        #expect(appState.articleReadOnOpenEvent?.sidebarSelection == .feed(article.feedID))
        #expect(appState.articleReadOnOpenEvent?.sidebarArticleFilter == .unread)
    }

    @Test
    func readerOpeningModeSafariViewSurvivesRedundantNilSelectionAfterReadEvent() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appState = AppState()
        let article = try insertArticle(
            into: harness,
            feedURL: "https://example.com/safari-redundant-selection.xml",
            externalID: "safari-redundant-selection",
            articleURL: "https://example.com/articles/safari-redundant-selection"
        )
        let safariRoute = ArticleSafariRoute(
            articleID: article.id,
            url: URL(string: article.url)!
        )
        try harness.dependencies.appSettingsRepository?.update(
            AppSettingsUpdate(
                articleOpeningMode: .safariView,
                markAsReadOnOpen: true
            )
        )

        harness.dependencies.appActions.selectArticle(id: article.id, using: appState)
        harness.dependencies.appActions.selectArticle(id: nil, using: appState)

        #expect(appState.selectedArticleID == nil)
        #expect(
            appState.selectedDetailRoute == .safari(
                safariRoute,
                dismissalTarget: .articleList
            )
        )
        #expect(appState.presentedSafariRoute == safariRoute)
    }

    @Test
    func readerOpeningModeSafariViewRespectsDisabledMarkAsReadOnOpenPolicy() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appState = AppState()
        let article = try insertArticle(
            into: harness,
            feedURL: "https://example.com/safari-read-on-open-disabled.xml",
            externalID: "safari-read-on-open-disabled",
            articleURL: "https://example.com/articles/safari-read-on-open-disabled"
        )
        try harness.dependencies.appSettingsRepository?.update(
            AppSettingsUpdate(
                articleOpeningMode: .safariView,
                markAsReadOnOpen: false
            )
        )

        harness.dependencies.appActions.selectArticle(id: article.id, using: appState)

        let persistedState = try harness.articleStateRepository.fetchStateSnapshot(
            feedID: article.feedID,
            articleExternalID: article.externalID
        )
        #expect(persistedState == nil)
        #expect(appState.articleReadOnOpenEvent == nil)
        #expect(appState.presentedSafariRoute?.articleID == article.id)
    }

    @Test
    func sourceArticlePolicyRoutesBetweenSafariViewAndExternalBrowser() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appState = AppState()
        let article = try insertArticle(
            into: harness,
            feedURL: "https://example.com/source-routing.xml",
            externalID: "source-routing",
            articleURL: "https://example.com/articles/source-routing",
            canonicalURL: "https://example.com/articles/source-routing/canonical"
        )
        let sourceURL = URL(string: "https://example.com/articles/source-routing/canonical")!
        let controller = ArticleScreenController()
        var externallyOpenedURLs: [URL] = []

        await controller.load(articleID: article.id, dependencies: harness.dependencies)
        try harness.dependencies.appSettingsRepository?.update(
            AppSettingsUpdate(articleSourceLinkOpeningPolicy: .inAppBrowser)
        )

        controller.openSourceArticle(
            dependencies: harness.dependencies,
            appState: appState,
            openExternalURL: { externallyOpenedURLs.append($0) }
        )

        #expect(appState.presentedSafariRoute == ArticleSafariRoute(articleID: article.id, url: sourceURL))
        #expect(externallyOpenedURLs.isEmpty)

        harness.dependencies.appActions.closePresentedArticleSafari(using: appState)
        try harness.dependencies.appSettingsRepository?.update(
            AppSettingsUpdate(articleSourceLinkOpeningPolicy: .externalBrowser)
        )

        controller.openSourceArticle(
            dependencies: harness.dependencies,
            appState: appState,
            openExternalURL: { externallyOpenedURLs.append($0) }
        )

        #expect(externallyOpenedURLs == [sourceURL])
        #expect(appState.presentedSafariRoute == nil)
        #expect(appState.selectedDetailRoute == .article(article.id))
    }

    @Test
    func bodyLinkPolicyRoutesBetweenSafariViewAndExternalBrowser() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appState = AppState()
        let article = try insertArticle(
            into: harness,
            feedURL: "https://example.com/body-link-routing.xml",
            externalID: "body-link-routing",
            articleURL: "https://example.com/articles/body-link-routing"
        )
        let tappedURL = URL(string: "https://example.com/guides/body-link")!
        let controller = ArticleScreenController()
        var externallyOpenedURLs: [URL] = []

        await controller.load(articleID: article.id, dependencies: harness.dependencies)
        try harness.dependencies.appSettingsRepository?.update(
            AppSettingsUpdate(articleBodyLinkOpeningPolicy: .inAppBrowser)
        )

        controller.handleBodyLinkTap(
            tappedURL,
            dependencies: harness.dependencies,
            appState: appState,
            openExternalURL: { externallyOpenedURLs.append($0) }
        )

        #expect(appState.presentedSafariRoute == ArticleSafariRoute(articleID: article.id, url: tappedURL))
        #expect(externallyOpenedURLs.isEmpty)

        harness.dependencies.appActions.closePresentedArticleSafari(using: appState)
        try harness.dependencies.appSettingsRepository?.update(
            AppSettingsUpdate(articleBodyLinkOpeningPolicy: .externalBrowser)
        )

        controller.handleBodyLinkTap(
            tappedURL,
            dependencies: harness.dependencies,
            appState: appState,
            openExternalURL: { externallyOpenedURLs.append($0) }
        )

        #expect(externallyOpenedURLs == [tappedURL])
        #expect(appState.presentedSafariRoute == nil)
        #expect(appState.selectedDetailRoute == .article(article.id))
    }

    private func insertArticle(
        into harness: TestHarness,
        feedURL: String,
        externalID: String,
        articleURL: String,
        canonicalURL: String? = nil
    ) throws -> Article {
        let feed = try #require(try harness.insertFeeds(urls: [feedURL]).first)
        let article = try harness.insertArticle(
            feed: feed,
            externalID: externalID,
            url: articleURL,
            title: externalID
        )
        article.canonicalURL = canonicalURL
        try harness.saveModelContext()
        return article
    }
}
