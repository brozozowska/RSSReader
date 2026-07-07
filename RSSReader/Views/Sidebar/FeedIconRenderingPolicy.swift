import SwiftUI

struct FeedIconRenderingPolicy {
    let containerSize: CGFloat
    let iconSize: CGFloat
    let cornerRadius: CGFloat
    let iconCornerRadius: CGFloat
    let borderWidth: CGFloat
    let backgroundOpacity: Double
    let borderOpacity: Double

    static func sidebar(colorScheme: ColorScheme) -> FeedIconRenderingPolicy {
        switch colorScheme {
        case .dark:
            FeedIconRenderingPolicy(
                containerSize: 20,
                iconSize: 18,
                cornerRadius: 5,
                iconCornerRadius: 4,
                borderWidth: 1,
                backgroundOpacity: 0.20,
                borderOpacity: 0.28
            )
        default:
            FeedIconRenderingPolicy(
                containerSize: 20,
                iconSize: 18,
                cornerRadius: 5,
                iconCornerRadius: 4,
                borderWidth: 1,
                backgroundOpacity: 0.18,
                borderOpacity: 0.24
            )
        }
    }
}
