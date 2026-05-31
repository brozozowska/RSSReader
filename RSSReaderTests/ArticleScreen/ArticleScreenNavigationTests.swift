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
    func articleScreenNavigationStateReportsBottomOverscrollProgressForNextArticle() {
        let shortPullState = ArticleScreenNavigationState.adjacentArticleOverscrollState(
            scrollGeometry: ReaderArticleScrollGeometry(
                contentHeight: 1_400,
                containerHeight: 700,
                boundsMaxY: 1_435
            )
        )

        #expect(shortPullState.nextProgress == 0.5)
        #expect(shortPullState.previousProgress == 0)
        #expect(shortPullState.readyDirection == nil)

        let readyState = ArticleScreenNavigationState.adjacentArticleOverscrollState(
            scrollGeometry: ReaderArticleScrollGeometry(
                contentHeight: 1_400,
                containerHeight: 700,
                boundsMaxY: 1_470
            )
        )

        #expect(readyState.nextProgress == 1)
        #expect(readyState.readyDirection == .next)
    }

    @Test
    func articleScreenNavigationStateStartsBottomOverscrollAtInsetAdjustedBoundary() {
        let restingState = ArticleScreenNavigationState.adjacentArticleOverscrollState(
            scrollGeometry: ReaderArticleScrollGeometry(
                contentHeight: 1_400,
                containerHeight: 700,
                contentInsetBottom: 96,
                boundsMaxY: 1_304
            )
        )

        #expect(restingState.nextProgress == 0)
        #expect(restingState.readyDirection == nil)

        let pullState = ArticleScreenNavigationState.adjacentArticleOverscrollState(
            scrollGeometry: ReaderArticleScrollGeometry(
                contentHeight: 1_400,
                containerHeight: 700,
                contentInsetBottom: 96,
                boundsMaxY: 1_339
            )
        )

        #expect(pullState.nextProgress == 0.5)
        #expect(pullState.readyDirection == nil)
    }

    @Test
    func articleScreenNavigationStateReportsTopOverscrollProgressForPreviousArticle() {
        let restingState = ArticleScreenNavigationState.adjacentArticleOverscrollState(
            scrollGeometry: ReaderArticleScrollGeometry(
                contentHeight: 1_400,
                containerHeight: 700,
                contentOffsetY: -16,
                contentInsetTop: 16
            )
        )

        #expect(restingState.previousProgress == 0)
        #expect(restingState.nextProgress == 0)
        #expect(restingState.readyDirection == nil)

        let shortPullState = ArticleScreenNavigationState.adjacentArticleOverscrollState(
            scrollGeometry: ReaderArticleScrollGeometry(
                contentHeight: 1_400,
                containerHeight: 700,
                contentOffsetY: -51,
                contentInsetTop: 16
            )
        )

        #expect(shortPullState.previousProgress == 0.5)
        #expect(shortPullState.nextProgress == 0)
        #expect(shortPullState.readyDirection == nil)

        let readyState = ArticleScreenNavigationState.adjacentArticleOverscrollState(
            scrollGeometry: ReaderArticleScrollGeometry(
                contentHeight: 1_400,
                containerHeight: 700,
                contentOffsetY: -86,
                contentInsetTop: 16
            )
        )

        #expect(readyState.previousProgress == 1)
        #expect(readyState.readyDirection == .previous)
    }

    @Test
    func articleScreenNavigationStateReportsBottomOverscrollForNonScrollableContentFromRestingOffset() {
        let restingState = ArticleScreenNavigationState.adjacentArticleOverscrollState(
            scrollGeometry: ReaderArticleScrollGeometry(
                contentHeight: 320,
                containerHeight: 700,
                contentOffsetY: -16,
                contentInsetTop: 16,
                boundsMaxY: 700
            )
        )

        #expect(restingState.previousProgress == 0)
        #expect(restingState.nextProgress == 0)
        #expect(restingState.readyDirection == nil)

        let shortPullState = ArticleScreenNavigationState.adjacentArticleOverscrollState(
            scrollGeometry: ReaderArticleScrollGeometry(
                contentHeight: 320,
                containerHeight: 700,
                contentOffsetY: 19,
                contentInsetTop: 16,
                boundsMaxY: 700
            )
        )

        #expect(shortPullState.nextProgress == 0.5)
        #expect(shortPullState.readyDirection == nil)

        let readyState = ArticleScreenNavigationState.adjacentArticleOverscrollState(
            scrollGeometry: ReaderArticleScrollGeometry(
                contentHeight: 320,
                containerHeight: 700,
                contentOffsetY: 54,
                contentInsetTop: 16,
                boundsMaxY: 700
            )
        )

        #expect(readyState.nextProgress == 1)
        #expect(readyState.readyDirection == .next)
    }

    @Test
    func articleScreenNavigationStateTriggersBoundaryHapticOnlyWhenOverscrollBecomesReady() {
        let restingState = ReaderArticleOverscrollNavigationState()
        let minusIndicatorState = ReaderArticleOverscrollNavigationState(nextProgress: 0.5)
        let readyState = ReaderArticleOverscrollNavigationState(nextProgress: 1)

        #expect(
            ArticleScreenNavigationState.shouldTriggerAdjacentArticleOverscrollReadyHaptic(
                previousState: restingState,
                newState: minusIndicatorState,
                hasTriggeredInCurrentGesture: false
            ) == false
        )
        #expect(
            ArticleScreenNavigationState.shouldTriggerAdjacentArticleOverscrollReadyHaptic(
                previousState: minusIndicatorState,
                newState: readyState,
                hasTriggeredInCurrentGesture: false
            )
        )
    }

    @Test
    func articleScreenNavigationStateDoesNotRepeatBoundaryHapticDuringSamePullGesture() {
        let readyState = ReaderArticleOverscrollNavigationState(previousProgress: 1)
        let reducedPullState = ReaderArticleOverscrollNavigationState(previousProgress: 0.75)

        #expect(
            ArticleScreenNavigationState.shouldTriggerAdjacentArticleOverscrollReadyHaptic(
                previousState: readyState,
                newState: readyState,
                hasTriggeredInCurrentGesture: false
            ) == false
        )
        #expect(
            ArticleScreenNavigationState.shouldTriggerAdjacentArticleOverscrollReadyHaptic(
                previousState: reducedPullState,
                newState: readyState,
                hasTriggeredInCurrentGesture: true
            ) == false
        )
    }
}
