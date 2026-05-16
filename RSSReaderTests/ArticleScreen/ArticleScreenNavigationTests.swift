import SwiftUI
import Testing
@testable import RSSReader

@Suite("Article Screen / Navigation")
@MainActor
struct ArticleScreenNavigationTests {
    @Test
    func articleScreenNavigationStateShowsBackButtonOnlyForCompactArticleContext() {
        #expect(
            ArticleScreenNavigationState.showsBackButton(
                horizontalSizeClass: .compact,
                articleSelection: UUID()
            )
        )
        #expect(
            ArticleScreenNavigationState.showsBackButton(
                horizontalSizeClass: .regular,
                articleSelection: UUID()
            ) == false
        )
        #expect(
            ArticleScreenNavigationState.showsBackButton(
                horizontalSizeClass: .compact,
                articleSelection: nil
            ) == false
        )
    }

    @Test
    func articleScreenNavigationStateRecognizesLeadingEdgeBackSwipe() {
        #expect(
            ArticleScreenNavigationState.shouldNavigateBackOnDrag(
                startLocationX: 12,
                translation: CGSize(width: 96, height: 8)
            )
        )
        #expect(
            ArticleScreenNavigationState.shouldNavigateBackOnDrag(
                startLocationX: 80,
                translation: CGSize(width: 96, height: 8)
            ) == false
        )
        #expect(
            ArticleScreenNavigationState.shouldNavigateBackOnDrag(
                startLocationX: 12,
                translation: CGSize(width: 40, height: 8)
            ) == false
        )
    }

    @Test
    func articleScreenNavigationStateRecognizesVerticalAdjacentArticleSwipes() {
        #expect(
            ArticleScreenNavigationState.adjacentArticleNavigationDirection(
                translation: CGSize(width: 12, height: -140)
            ) == .next
        )
        #expect(
            ArticleScreenNavigationState.adjacentArticleNavigationDirection(
                translation: CGSize(width: 12, height: 140)
            ) == .previous
        )
        #expect(
            ArticleScreenNavigationState.adjacentArticleNavigationDirection(
                translation: CGSize(width: 12, height: -80)
            ) == nil
        )
        #expect(
            ArticleScreenNavigationState.adjacentArticleNavigationDirection(
                translation: CGSize(width: 120, height: -140)
            ) == nil
        )
    }

    @Test
    func articleScreenNavigationStateRequiresBottomOverscrollForNextArticleSwipe() {
        #expect(
            ArticleScreenNavigationState.adjacentArticleOverscrollDirection(
                scrollGeometry: ReaderArticleScrollGeometry(
                    contentOffsetY: 500,
                    contentHeight: 1_400,
                    containerHeight: 700
                )
            ) == nil
        )

        #expect(
            ArticleScreenNavigationState.adjacentArticleOverscrollDirection(
                scrollGeometry: ReaderArticleScrollGeometry(
                    contentOffsetY: 724,
                    contentHeight: 1_400,
                    containerHeight: 700
                )
            ) == .next
        )
    }

    @Test
    func articleScreenNavigationStateRequiresTopOverscrollForPreviousArticleSwipe() {
        #expect(
            ArticleScreenNavigationState.adjacentArticleOverscrollDirection(
                scrollGeometry: ReaderArticleScrollGeometry(
                    contentOffsetY: 100,
                    contentHeight: 1_400,
                    containerHeight: 700
                )
            ) == nil
        )

        #expect(
            ArticleScreenNavigationState.adjacentArticleOverscrollDirection(
                scrollGeometry: ReaderArticleScrollGeometry(
                    contentOffsetY: -24,
                    contentHeight: 1_400,
                    containerHeight: 700
                )
            ) == .previous
        )
    }

    @Test
    func articleScreenNavigationStateIgnoresShortOverscrollPulls() {
        #expect(
            ArticleScreenNavigationState.adjacentArticleOverscrollDirection(
                scrollGeometry: ReaderArticleScrollGeometry(
                    contentOffsetY: 720,
                    contentHeight: 1_400,
                    containerHeight: 700
                )
            ) == nil
        )

        #expect(
            ArticleScreenNavigationState.adjacentArticleOverscrollDirection(
                scrollGeometry: ReaderArticleScrollGeometry(
                    contentOffsetY: -20,
                    contentHeight: 1_400,
                    containerHeight: 700
                )
            ) == nil
        )
    }
}
