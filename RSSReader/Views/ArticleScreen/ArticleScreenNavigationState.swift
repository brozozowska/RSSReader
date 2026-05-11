import SwiftUI

enum ArticleScreenNavigationState {
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
}
