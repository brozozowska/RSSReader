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
