import SwiftUI

struct ReaderAdjacentArticleOverscrollIndicator: View {
    let systemImage: String
    let progress: CGFloat
    let isReady: Bool

    var body: some View {
        if progress >= ReaderChromeUnderlayLayout.indicatorVisibilityThreshold {
            Image(systemName: isReady ? systemImage : "minus")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(isReady ? .primary : .secondary)
                .contentTransition(
                    .symbolEffect(
                        .replace.magic(fallback: .downUp.byLayer),
                        options: .nonRepeating
                    )
                )
                .scaleEffect(0.4 + 0.6 * progress)
                .opacity(0.25 + 0.75 * progress)
                .animation(.snappy(duration: 0.18), value: isReady)
                .accessibilityHidden(true)
        }
    }
}
