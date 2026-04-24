import SwiftUI
import Testing
@testable import RSSReader

@Suite("Shell / Navigation")
@MainActor
struct ReadingShellNavigationTests {
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
    func readingShellNavigationStateBuildsWebViewDestinationForWebViewRoute() {
        let route = ArticleWebViewRoute(
            articleID: UUID(),
            url: URL(string: "https://example.com/web-shell-destination")!
        )

        #expect(
            ReadingShellDetailNavigationState.detailDestination(
                route: .webView(route),
                selectedArticleID: route.articleID
            ) == .webView(route)
        )
    }

    @Test
    func readingShellCompactNavigationStateSelectsPreferredCompactColumnForCurrentContext() {
        #expect(
            ReadingShellCompactNavigationState.preferredCompactColumn(
                sourceSelection: nil,
                articleSelection: nil
            ) == .sidebar
        )
        #expect(
            ReadingShellCompactNavigationState.preferredCompactColumn(
                sourceSelection: .unread,
                articleSelection: nil
            ) == .content
        )
        #expect(
            ReadingShellCompactNavigationState.preferredCompactColumn(
                sourceSelection: .feed(UUID()),
                articleSelection: UUID()
            ) == .detail
        )
    }

    @Test
    func readingShellCompactNavigationStateShowsArticlesBackButtonOnlyInCompactSourceContext() {
        #expect(
            ReadingShellCompactNavigationState.showsArticlesBackButton(
                horizontalSizeClass: .compact,
                sourceSelection: .starred
            )
        )
        #expect(
            ReadingShellCompactNavigationState.showsArticlesBackButton(
                horizontalSizeClass: .regular,
                sourceSelection: .starred
            ) == false
        )
        #expect(
            ReadingShellCompactNavigationState.showsArticlesBackButton(
                horizontalSizeClass: .compact,
                sourceSelection: nil
            ) == false
        )
    }

    @Test
    func readingShellCompactNavigationStateRecognizesLeadingEdgeBackSwipeToSources() {
        #expect(
            ReadingShellCompactNavigationState.shouldNavigateBackToSourcesOnDrag(
                startLocationX: 12,
                translation: CGSize(width: 96, height: 8)
            )
        )
        #expect(
            ReadingShellCompactNavigationState.shouldNavigateBackToSourcesOnDrag(
                startLocationX: 64,
                translation: CGSize(width: 96, height: 8)
            ) == false
        )
        #expect(
            ReadingShellCompactNavigationState.shouldNavigateBackToSourcesOnDrag(
                startLocationX: 12,
                translation: CGSize(width: 40, height: 8)
            ) == false
        )
        #expect(
            ReadingShellCompactNavigationState.shouldNavigateBackToSourcesOnDrag(
                startLocationX: 12,
                translation: CGSize(width: 96, height: 72)
            ) == false
        )
    }
}
