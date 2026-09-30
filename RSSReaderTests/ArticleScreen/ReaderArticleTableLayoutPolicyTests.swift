import CoreGraphics
import Testing
@testable import RSSReader

@Suite("Reader article table layout policy")
struct ReaderArticleTableLayoutPolicyTests {
    private let policy = ReaderArticleTableLayoutPolicy()

    @Test("Compact widths use cards for two through five columns", arguments: 2...5)
    func compactWidthsUseCards(columnCount: Int) {
        #expect(
            policy.presentation(
                availableWidth: 390,
                columnCount: columnCount,
                textSize: .standard
            ) == .cards
        )
    }

    @Test("Regular width uses a grid when every column has enough room")
    func regularWidthUsesGrid() {
        #expect(
            policy.presentation(
                availableWidth: 900,
                columnCount: 5,
                textSize: .standard
            ) == .grid(columnWidth: 180)
        )
    }

    @Test("Split View width returns a grid to cards")
    func splitViewWidthUsesCards() {
        #expect(
            policy.presentation(
                availableWidth: 600,
                columnCount: 5,
                textSize: .standard
            ) == .cards
        )
    }

    @Test("Larger text raises the minimum grid width")
    func largerTextRaisesMinimumWidth() {
        #expect(policy.presentation(availableWidth: 600, columnCount: 4, textSize: .standard) != .cards)
        #expect(policy.presentation(availableWidth: 600, columnCount: 4, textSize: .extraLarge) == .cards)
    }

    @Test("Accessibility text sizes always use cards")
    func accessibilityTextUsesCards() {
        #expect(
            policy.presentation(
                availableWidth: 1_400,
                columnCount: 3,
                textSize: .accessibility
            ) == .cards
        )
    }

    @Test("Very wide semantic tables use the bounded cards fallback")
    func manyColumnsUseCards() {
        #expect(
            policy.presentation(
                availableWidth: 1_400,
                columnCount: 6,
                textSize: .standard
            ) == .cards
        )
    }
}
