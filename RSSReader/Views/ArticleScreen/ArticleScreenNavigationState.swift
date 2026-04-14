import SwiftUI

enum ArticleScreenNavigationState {
    static func showsBackButton(
        horizontalSizeClass: UserInterfaceSizeClass?,
        articleSelection: UUID?
    ) -> Bool {
        horizontalSizeClass == .compact && articleSelection != nil
    }

    static func shouldNavigateBackOnDrag(
        startLocationX: CGFloat,
        translation: CGSize
    ) -> Bool {
        startLocationX <= 32
            && translation.width >= 80
            && abs(translation.height) <= 48
    }
}
