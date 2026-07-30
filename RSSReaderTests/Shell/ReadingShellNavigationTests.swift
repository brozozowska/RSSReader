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

}
