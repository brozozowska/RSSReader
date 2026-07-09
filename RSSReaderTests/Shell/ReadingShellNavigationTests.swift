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
        #expect(appState.selectedArticleID == nil)
        #expect(appState.selectedDetailRoute == .none)
        #expect(
            ReadingShellCompactNavigationState.preferredCompactColumn(
                sidebarSelection: appState.selectedSidebarSelection,
                articleSelection: appState.selectedArticleID
            ) == .sidebar
        )
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
    func readingShellCompactNavigationStateSelectsPreferredCompactColumnForCurrentContext() {
        #expect(
            ReadingShellCompactNavigationState.preferredCompactColumn(
                sidebarSelection: nil,
                articleSelection: nil
            ) == .sidebar
        )
        #expect(
            ReadingShellCompactNavigationState.preferredCompactColumn(
                sidebarSelection: .unread,
                articleSelection: nil
            ) == .content
        )
        #expect(
            ReadingShellCompactNavigationState.preferredCompactColumn(
                sidebarSelection: .feed(UUID()),
                articleSelection: UUID()
            ) == .detail
        )
    }

    @Test
    func readingShellCompactNavigationStateShowsArticlesBackButtonOnlyInCompactSidebarContext() {
        #expect(
            ReadingShellCompactNavigationState.showsArticlesBackButton(
                horizontalSizeClass: .compact,
                sidebarSelection: .starred
            )
        )
        #expect(
            ReadingShellCompactNavigationState.showsArticlesBackButton(
                horizontalSizeClass: .regular,
                sidebarSelection: .starred
            ) == false
        )
        #expect(
            ReadingShellCompactNavigationState.showsArticlesBackButton(
                horizontalSizeClass: .compact,
                sidebarSelection: nil
            ) == false
        )
    }

    @Test
    func readingShellCompactNavigationStateRecognizesLTRLeadingEdgeBackSwipeToSidebar() {
        #expect(
            ReadingShellCompactNavigationState.shouldNavigateBackToSidebarOnDrag(
                startLocationX: 12,
                containerWidth: 390,
                layoutDirection: .leftToRight,
                translation: CGSize(width: 96, height: 8)
            )
        )
        #expect(
            ReadingShellCompactNavigationState.shouldNavigateBackToSidebarOnDrag(
                startLocationX: 64,
                containerWidth: 390,
                layoutDirection: .leftToRight,
                translation: CGSize(width: 96, height: 8)
            ) == false
        )
        #expect(
            ReadingShellCompactNavigationState.shouldNavigateBackToSidebarOnDrag(
                startLocationX: 12,
                containerWidth: 390,
                layoutDirection: .leftToRight,
                translation: CGSize(width: 40, height: 8)
            ) == false
        )
        #expect(
            ReadingShellCompactNavigationState.shouldNavigateBackToSidebarOnDrag(
                startLocationX: 12,
                containerWidth: 390,
                layoutDirection: .leftToRight,
                translation: CGSize(width: 96, height: 72)
            ) == false
        )
    }

    @Test
    func readingShellCompactNavigationStateRecognizesRTLLeadingEdgeBackSwipeToSidebar() {
        #expect(
            ReadingShellCompactNavigationState.shouldNavigateBackToSidebarOnDrag(
                startLocationX: 378,
                containerWidth: 390,
                layoutDirection: .rightToLeft,
                translation: CGSize(width: -96, height: 8)
            )
        )
        #expect(
            ReadingShellCompactNavigationState.shouldNavigateBackToSidebarOnDrag(
                startLocationX: 12,
                containerWidth: 390,
                layoutDirection: .rightToLeft,
                translation: CGSize(width: -96, height: 8)
            ) == false
        )
        #expect(
            ReadingShellCompactNavigationState.shouldNavigateBackToSidebarOnDrag(
                startLocationX: 378,
                containerWidth: 390,
                layoutDirection: .rightToLeft,
                translation: CGSize(width: 96, height: 8)
            ) == false
        )
    }
}
