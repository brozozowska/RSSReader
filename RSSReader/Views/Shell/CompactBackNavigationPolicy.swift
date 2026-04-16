import SwiftUI

enum CompactBackNavigationPolicy {
    static func showsBackButton(
        horizontalSizeClass: UserInterfaceSizeClass?,
        hasSelection: Bool
    ) -> Bool {
        horizontalSizeClass == .compact && hasSelection
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
