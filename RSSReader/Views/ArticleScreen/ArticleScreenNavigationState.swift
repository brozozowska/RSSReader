import SwiftUI

enum ArticleScreenNavigationState {
    private static let previousArticleOverscrollThresholdFraction: CGFloat = 0.1
    private static let nextArticleOverscrollThresholdFraction: CGFloat = 0.1
    private static let openSourceArticleHorizontalTranslationThreshold: CGFloat = 96
    private static let openSourceArticleVerticalTranslationTolerance: CGFloat = 48
    private static let openSourceArticleCommitProgressThreshold: CGFloat = 0.33

    static func showsBackButton(
        horizontalSizeClass: UserInterfaceSizeClass?,
        articleSelection: UUID?
    ) -> Bool {
        CompactBackNavigationPolicy.showsBackButton(
            horizontalSizeClass: horizontalSizeClass,
            hasSelection: articleSelection != nil
        )
    }

    static func shouldNavigateBackOnDrag(
        startLocationX: CGFloat,
        containerWidth: CGFloat,
        layoutDirection: LayoutDirection,
        translation: CGSize
    ) -> Bool {
        CompactBackNavigationPolicy.shouldNavigateBackOnDrag(
            startLocationX: startLocationX,
            containerWidth: containerWidth,
            layoutDirection: layoutDirection,
            translation: translation
        )
    }

    static func shouldOpenSourceArticleOnDrag(
        layoutDirection: LayoutDirection,
        containerWidth: CGFloat,
        translation: CGSize
    ) -> Bool {
        let progress = openSourceArticleSwipeProgress(
            layoutDirection: layoutDirection,
            containerWidth: containerWidth,
            translation: translation
        )
        return openSourceArticleDirectionalTranslation(
            layoutDirection: layoutDirection,
            translation: translation
        ) >= openSourceArticleHorizontalTranslationThreshold
            && progress >= openSourceArticleCommitProgressThreshold
    }

    static func openSourceArticleSwipeProgress(
        layoutDirection: LayoutDirection,
        containerWidth: CGFloat,
        translation: CGSize
    ) -> CGFloat {
        guard containerWidth > 0 else { return 0 }
        guard abs(translation.height) <= openSourceArticleVerticalTranslationTolerance else {
            return 0
        }

        let directionalTranslation = openSourceArticleDirectionalTranslation(
            layoutDirection: layoutDirection,
            translation: translation
        )
        return min(max(directionalTranslation / containerWidth, 0), 1)
    }

    private static func openSourceArticleDirectionalTranslation(
        layoutDirection: LayoutDirection,
        translation: CGSize
    ) -> CGFloat {
        switch layoutDirection {
        case .leftToRight:
            -translation.width
        case .rightToLeft:
            translation.width
        @unknown default:
            -translation.width
        }
    }

    static func adjacentArticleOverscrollState(
        scrollGeometry: ReaderArticleScrollGeometry
    ) -> ReaderArticleOverscrollNavigationState {
        let previousThreshold = max(1, scrollGeometry.containerHeight * previousArticleOverscrollThresholdFraction)
        let nextThreshold = max(1, scrollGeometry.containerHeight * nextArticleOverscrollThresholdFraction)
        let previousProgress = min(scrollGeometry.topOverscrollDistance / previousThreshold, 1)
        let nextProgress = min(scrollGeometry.bottomOverscrollDistance / nextThreshold, 1)

        return ReaderArticleOverscrollNavigationState(
            previousProgress: previousProgress,
            nextProgress: nextProgress
        )
    }

    static func shouldTriggerAdjacentArticleOverscrollReadyHaptic(
        previousState: ReaderArticleOverscrollNavigationState,
        newState: ReaderArticleOverscrollNavigationState,
        hasTriggeredInCurrentGesture: Bool
    ) -> Bool {
        guard hasTriggeredInCurrentGesture == false else { return false }

        return previousState.readyDirection == nil && newState.readyDirection != nil
    }
}

struct ReaderArticleOverscrollNavigationState: Equatable {
    var previousProgress: CGFloat = 0
    var nextProgress: CGFloat = 0

    var readyDirection: ReaderAdjacentArticleNavigationDirection? {
        if nextProgress >= 1 {
            return .next
        }

        if previousProgress >= 1 {
            return .previous
        }

        return nil
    }
}

struct ReaderArticleScrollGeometry: Equatable {
    var contentHeight: CGFloat
    var containerHeight: CGFloat
    var contentOffsetY: CGFloat
    var contentInsetTop: CGFloat
    var contentInsetBottom: CGFloat
    var boundsMaxY: CGFloat

    init(
        contentHeight: CGFloat = 0,
        containerHeight: CGFloat = 0,
        contentOffsetY: CGFloat = 0,
        contentInsetTop: CGFloat = 0,
        contentInsetBottom: CGFloat = 0,
        boundsMaxY: CGFloat = 0
    ) {
        self.contentHeight = contentHeight
        self.containerHeight = containerHeight
        self.contentOffsetY = contentOffsetY
        self.contentInsetTop = contentInsetTop
        self.contentInsetBottom = contentInsetBottom
        self.boundsMaxY = boundsMaxY
    }

    var topOverscrollDistance: CGFloat {
        max(0, -(contentOffsetY + contentInsetTop))
    }

    var bottomOverscrollDistance: CGFloat {
        guard isVerticallyScrollable else {
            return max(0, contentOffsetY + contentInsetTop)
        }

        return max(0, boundsMaxY - bottomOverscrollBoundaryY)
    }

    private var isVerticallyScrollable: Bool {
        contentHeight > containerHeight
    }

    private var bottomOverscrollBoundaryY: CGFloat {
        max(contentHeight - contentInsetBottom, containerHeight)
    }
}
