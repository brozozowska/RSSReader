import SwiftUI
import Testing
@testable import RSSReader

@Suite("Article Screen / Navigation")
@MainActor
struct ArticleScreenNavigationTests {
    @Test(arguments: [LayoutDirection.leftToRight, .rightToLeft])
    func sourceSwipeIgnoresGesturesStartingInsideCodeBlocks(_ direction: LayoutDirection) {
        let codeFrame = CGRect(x: 16, y: 200, width: 288, height: 120)
        let translation = CGSize(width: direction == .leftToRight ? -160 : 160, height: 8)
        let start = CGPoint(x: 160, y: 240)
        #expect(ArticleScreenNavigationState.openSourceArticleSwipeProgress(
            layoutDirection: direction, containerWidth: 320, translation: translation,
            startLocation: start, excludedSourceSwipeRegions: [codeFrame]
        ) == 0)
        #expect(!ArticleScreenNavigationState.shouldOpenSourceArticleOnDrag(
            layoutDirection: direction, containerWidth: 320, translation: translation,
            startLocation: start, excludedSourceSwipeRegions: [codeFrame]
        ))

        // The gesture belongs to its starting surface even if it subsequently crosses a code block.
        let outsideStart = CGPoint(x: direction == .leftToRight ? 315 : 5, y: 240)
        #expect(ArticleScreenNavigationState.openSourceArticleSwipeProgress(
            layoutDirection: direction, containerWidth: 320, translation: translation,
            startLocation: outsideStart, excludedSourceSwipeRegions: [codeFrame]
        ) == 0.5)
        #expect(ArticleScreenNavigationState.shouldOpenSourceArticleOnDrag(
            layoutDirection: direction, containerWidth: 320, translation: translation,
            startLocation: outsideStart, excludedSourceSwipeRegions: [codeFrame]
        ))
    }

    @Test
    func articleScreenNavigationStateRecognizesLTRTrailingToLeadingOpenSourceSwipe() {
        #expect(
            ArticleScreenNavigationState.shouldOpenSourceArticleOnDrag(
                layoutDirection: .leftToRight,
                containerWidth: 320,
                translation: CGSize(width: -128, height: 8)
            )
        )
        #expect(
            ArticleScreenNavigationState.shouldOpenSourceArticleOnDrag(
                layoutDirection: .leftToRight,
                containerWidth: 320,
                translation: CGSize(width: -64, height: 8)
            ) == false
        )
        #expect(
            ArticleScreenNavigationState.shouldOpenSourceArticleOnDrag(
                layoutDirection: .leftToRight,
                containerWidth: 320,
                translation: CGSize(width: 112, height: 8)
            ) == false
        )
        #expect(
            ArticleScreenNavigationState.openSourceArticleSwipeProgress(
                layoutDirection: .leftToRight,
                containerWidth: 320,
                translation: CGSize(width: -160, height: 8)
            ) == 0.5
        )
    }

    @Test
    func articleScreenNavigationStateMirrorsOpenSourceSwipeInRTL() {
        #expect(
            ArticleScreenNavigationState.shouldOpenSourceArticleOnDrag(
                layoutDirection: .rightToLeft,
                containerWidth: 320,
                translation: CGSize(width: 128, height: 8)
            )
        )
        #expect(
            ArticleScreenNavigationState.shouldOpenSourceArticleOnDrag(
                layoutDirection: .rightToLeft,
                containerWidth: 320,
                translation: CGSize(width: -112, height: 8)
            ) == false
        )
        #expect(
            ArticleScreenNavigationState.openSourceArticleSwipeProgress(
                layoutDirection: .rightToLeft,
                containerWidth: 320,
                translation: CGSize(width: 160, height: 8)
            ) == 0.5
        )
    }

    @Test
    func articleScreenNavigationStateDoesNotTreatVerticalOverscrollAsOpenSourceSwipe() {
        #expect(
            ArticleScreenNavigationState.shouldOpenSourceArticleOnDrag(
                layoutDirection: .leftToRight,
                containerWidth: 320,
                translation: CGSize(width: -112, height: 72)
            ) == false
        )
        #expect(
            ArticleScreenNavigationState.shouldOpenSourceArticleOnDrag(
                layoutDirection: .rightToLeft,
                containerWidth: 320,
                translation: CGSize(width: 112, height: 72)
            ) == false
        )
        #expect(
            ArticleScreenNavigationState.openSourceArticleSwipeProgress(
                layoutDirection: .leftToRight,
                containerWidth: 320,
                translation: CGSize(width: -160, height: 72)
            ) == 0
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
