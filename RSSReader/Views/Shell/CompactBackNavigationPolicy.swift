import SwiftUI

enum CompactBackNavigationPolicy {
    private static let edgeActivationWidth: CGFloat = 32
    private static let horizontalTranslationThreshold: CGFloat = 80
    private static let verticalTranslationTolerance: CGFloat = 48

    static func shouldNavigateBackOnDrag(
        startLocationX: CGFloat,
        containerWidth: CGFloat,
        layoutDirection: LayoutDirection,
        translation: CGSize
    ) -> Bool {
        guard abs(translation.height) <= verticalTranslationTolerance else {
            return false
        }

        switch layoutDirection {
        case .leftToRight:
            return startLocationX <= edgeActivationWidth
                && translation.width >= horizontalTranslationThreshold
        case .rightToLeft:
            return startLocationX >= containerWidth - edgeActivationWidth
                && translation.width <= -horizontalTranslationThreshold
        @unknown default:
            return startLocationX <= edgeActivationWidth
                && translation.width >= horizontalTranslationThreshold
        }
    }
}
