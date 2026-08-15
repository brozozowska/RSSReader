import SwiftUI
import Testing
@testable import RSSReader

@Suite("Shell / Navigation")
@MainActor
struct ReadingShellNavigationTests {
    @Test
    func readingShellInitialAppStateStartsOnSidebarInCompactNavigation() {
        let appState = AppState()

        #expect(appState.selectedSidebarSelection == nil)
        #expect(appState.presentedSidebarSelection == nil)
        #expect(appState.selectedArticleID == nil)
        #expect(appState.selectedDetailRoute == .none)
    }

    @Test
    func readingShellNavigationStateBuildsDetailDestinationsForNoneAndArticleRoutes() {
        let articleID = UUID()

        #expect(
            ReadingShellDetailNavigationState.detailDestination(
                route: .none,
                selectedArticleID: nil
            ) == .none
        )
        #expect(
            ReadingShellDetailNavigationState.detailDestination(
                route: .none,
                selectedArticleID: articleID
            ) == .article(articleID)
        )
        #expect(
            ReadingShellDetailNavigationState.detailDestination(
                route: .article(articleID),
                selectedArticleID: nil
            ) == .article(articleID)
        )
    }

    @Test
    func readingShellNavigationStateKeepsArticleDestinationBehindSafariRoute() {
        let route = ArticleSafariRoute(
            articleID: UUID(),
            url: URL(string: "https://example.com/web-shell-destination")!
        )

        #expect(
            ReadingShellDetailNavigationState.detailDestination(
                route: .safari(route, dismissalTarget: .article),
                selectedArticleID: route.articleID
            ) == .article(route.articleID)
        )
    }

    @Test
    func readingShellNavigationStateDoesNotBuildReaderDestinationBehindDirectSafariRoute() {
        let route = ArticleSafariRoute(
            articleID: UUID(),
            url: URL(string: "https://example.com/direct-safari-shell-destination")!
        )

        #expect(
            ReadingShellDetailNavigationState.detailDestination(
                route: .safari(route, dismissalTarget: .articleList),
                selectedArticleID: nil
            ) == .none
        )
    }

    @Test
    func readingShellSafariDismissalTracksReaderOwnedTargetThroughSingleCommit() throws {
        let articleID = UUID()
        let safariRoute = ArticleSafariRoute(
            articleID: articleID,
            url: URL(string: "https://example.com/reader-owned-dismissal")!
        )
        let sourceRoute = ReadingDetailRoute.safari(
            safariRoute,
            dismissalTarget: .article
        )
        var interaction = ReadingShellSafariDismissalInteractionState()

        interaction.update(
            sourceRoute: sourceRoute,
            selectedArticleID: articleID,
            progress: 0.35
        )

        #expect(interaction.retainedSafariRoute == safariRoute)
        #expect(interaction.progress == 0.35)
        #expect(interaction.transition?.dismissalTarget == .article)
        #expect(interaction.transition?.destination == .article(articleID))

        let preparedTransition = interaction.prepareCommit(
            sourceRoute: sourceRoute,
            selectedArticleID: articleID
        )
        let committedTransition = try #require(preparedTransition)
        interaction.finish(committedTransition)
        interaction.finish(committedTransition)

        #expect(interaction.progress == 1)

        interaction.complete(committedTransition)
        interaction.complete(committedTransition)

        #expect(interaction.transition == nil)
    }

    @Test
    func readingShellSafariDismissalCancelsDirectTargetWithoutChangingRoute() {
        let appState = AppState()
        let articleID = UUID()
        let articleURL = URL(string: "https://example.com/direct-dismissal-cancel")!
        appState.presentSafariFromArticleList(articleID: articleID, url: articleURL)
        let sourceRoute = appState.selectedDetailRoute
        var interaction = ReadingShellSafariDismissalInteractionState()

        interaction.update(
            sourceRoute: sourceRoute,
            selectedArticleID: appState.selectedArticleID,
            progress: 1.4
        )

        #expect(interaction.progress == 1)
        #expect(interaction.transition?.dismissalTarget == .articleList)
        #expect(interaction.transition?.destination == ReadingShellDetailDestination.none)

        interaction.cancel()

        #expect(interaction.transition == nil)
        #expect(appState.selectedDetailRoute == sourceRoute)
        #expect(appState.presentedSafariRoute?.articleID == articleID)
    }

    @Test
    func readingShellSafariDismissalCancelsReaderOwnedTargetWithoutChangingRoute() {
        let appState = AppState()
        let articleID = UUID()
        appState.selectArticle(articleID)
        appState.presentSafari(
            articleID: articleID,
            url: URL(string: "https://example.com/reader-owned-dismissal-cancel")!
        )
        let sourceRoute = appState.selectedDetailRoute
        var interaction = ReadingShellSafariDismissalInteractionState()

        interaction.update(
            sourceRoute: sourceRoute,
            selectedArticleID: articleID,
            progress: 0.45
        )
        interaction.cancel()

        #expect(interaction.transition == nil)
        #expect(appState.selectedDetailRoute == sourceRoute)
        #expect(appState.selectedArticleID == articleID)
    }

    @Test
    func readingShellSafariDismissalCommitsDirectTargetOnce() throws {
        let articleID = UUID()
        let safariRoute = ArticleSafariRoute(
            articleID: articleID,
            url: URL(string: "https://example.com/direct-dismissal-commit")!
        )
        let sourceRoute = ReadingDetailRoute.safari(
            safariRoute,
            dismissalTarget: .articleList
        )
        var interaction = ReadingShellSafariDismissalInteractionState()

        interaction.update(
            sourceRoute: sourceRoute,
            selectedArticleID: nil,
            progress: 0.25
        )
        let preparedTransition = interaction.prepareCommit(
            sourceRoute: sourceRoute,
            selectedArticleID: nil
        )
        let committedTransition = try #require(preparedTransition)
        interaction.finish(committedTransition)

        #expect(interaction.progress == 1)
        #expect(interaction.transition?.dismissalTarget == .articleList)
        #expect(interaction.transition?.destination == ReadingShellDetailDestination.none)

        interaction.complete(committedTransition)
        interaction.complete(committedTransition)

        #expect(interaction.transition == nil)
    }

}
