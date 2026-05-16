import SwiftUI

enum ArticleScreenNavigationState {
    private static let adjacentArticleOverscrollDistance: CGFloat = 24

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
        translation: CGSize
    ) -> Bool {
        CompactBackNavigationPolicy.shouldNavigateBackOnDrag(
            startLocationX: startLocationX,
            translation: translation
        )
    }

    static func adjacentArticleNavigationDirection(
        translation: CGSize
    ) -> ReaderAdjacentArticleNavigationDirection? {
        let verticalDistance = translation.height
        let horizontalDistance = abs(translation.width)
        let absoluteVerticalDistance = abs(verticalDistance)

        guard absoluteVerticalDistance >= 120,
              absoluteVerticalDistance > horizontalDistance * 1.5 else {
            return nil
        }

        return verticalDistance < 0 ? .next : .previous
    }

    static func adjacentArticleOverscrollDirection(
        scrollGeometry: ReaderArticleScrollGeometry
    ) -> ReaderAdjacentArticleNavigationDirection? {
        if scrollGeometry.bottomOverscrollDistance >= adjacentArticleOverscrollDistance {
            return .next
        }

        if scrollGeometry.topOverscrollDistance >= adjacentArticleOverscrollDistance {
            return .previous
        }

        return nil
    }
}

struct ReaderArticleScrollGeometry: Equatable {
    var contentOffsetY: CGFloat
    var contentHeight: CGFloat
    var containerHeight: CGFloat
    var topInset: CGFloat
    var bottomInset: CGFloat

    init(
        contentOffsetY: CGFloat = 0,
        contentHeight: CGFloat = 0,
        containerHeight: CGFloat = 0,
        topInset: CGFloat = 0,
        bottomInset: CGFloat = 0
    ) {
        self.contentOffsetY = contentOffsetY
        self.contentHeight = contentHeight
        self.containerHeight = containerHeight
        self.topInset = topInset
        self.bottomInset = bottomInset
    }

    var topOverscrollDistance: CGFloat {
        max(0, topBoundaryOffsetY - contentOffsetY)
    }

    var bottomOverscrollDistance: CGFloat {
        max(0, contentOffsetY - bottomBoundaryOffsetY)
    }

    private var topBoundaryOffsetY: CGFloat {
        topInset
    }

    private var bottomBoundaryOffsetY: CGFloat {
        max(topBoundaryOffsetY, contentHeight + bottomInset - containerHeight)
    }
}
