import SwiftUI
import Testing
@testable import RSSReader

@Suite("WebView Screen / Navigation")
@MainActor
struct WebViewScreenNavigationTests {
    @Test
    func webViewScreenNavigationStateClosesOnLeftEdgeHorizontalDrag() {
        #expect(
            WebViewScreenNavigationState.shouldCloseOnDrag(
                startLocationX: 12,
                translation: CGSize(width: 96, height: 10)
            )
        )
    }

    @Test
    func webViewScreenNavigationStateIgnoresDragsAwayFromLeftEdge() {
        #expect(
            WebViewScreenNavigationState.shouldCloseOnDrag(
                startLocationX: 48,
                translation: CGSize(width: 96, height: 8)
            ) == false
        )
    }

    @Test
    func webViewScreenNavigationStateIgnoresMostlyVerticalDrags() {
        #expect(
            WebViewScreenNavigationState.shouldCloseOnDrag(
                startLocationX: 10,
                translation: CGSize(width: 96, height: 64)
            ) == false
        )
    }
}
