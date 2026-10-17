import SwiftUI

/// Symbols describe persisted article state; action labels describe the next operation.
enum ArticleStateSymbols {
    static func read(isRead: Bool) -> String {
        isRead ? "circle" : "circle.fill"
    }

    static func starred(isStarred: Bool) -> String {
        isStarred ? "star.fill" : "star"
    }

    static let markAllAsRead = read(isRead: true)
}

/// Keep explicit outline/fill choices even in containers that supply a symbol variant.
struct ArticleStateSymbol: View {
    let systemName: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: systemName)
            .environment(\.symbolVariants, .none)
            .contentTransition(
                reduceMotion
                    ? .identity
                    : .symbolEffect(.replace.magic(fallback: .downUp.byLayer), options: .nonRepeating)
            )
            .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: systemName)
            .transaction {
                if reduceMotion {
                    $0.animation = nil
                    $0.disablesAnimations = true
                }
            }
    }
}
