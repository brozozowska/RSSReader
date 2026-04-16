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
}
