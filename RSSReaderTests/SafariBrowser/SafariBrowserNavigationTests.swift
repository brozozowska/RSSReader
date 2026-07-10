import Foundation
import SwiftUI
import Testing
@testable import RSSReader

@Suite("Safari Browser / Navigation")
@MainActor
struct SafariBrowserNavigationTests {
    @Test
    func safariBrowserNavigationDismissRestoresArticleDetailRoute() {
        let appState = AppState()
        let articleID = UUID()
        let articleURL = URL(string: "https://example.com/articles/safari-navigation")!

        appState.presentSafari(articleID: articleID, url: articleURL)
        appState.dismissPresentedSafari()

        #expect(appState.selectedArticleID == articleID)
        #expect(appState.selectedDetailRoute == .article(articleID))
        #expect(appState.presentedSafariRoute == nil)
    }

    @Test
    func safariBrowserNavigationRecognizesLTRLeadingEdgeBackSwipe() {
        #expect(
            SafariBrowserNavigationState.shouldDismissSafariOnDrag(
                startLocationX: 12,
                containerWidth: 390,
                layoutDirection: .leftToRight,
                translation: CGSize(width: 96, height: 8)
            )
        )
        #expect(
            SafariBrowserNavigationState.shouldDismissSafariOnDrag(
                startLocationX: 64,
                containerWidth: 390,
                layoutDirection: .leftToRight,
                translation: CGSize(width: 96, height: 8)
            ) == false
        )
        #expect(
            SafariBrowserNavigationState.shouldDismissSafariOnDrag(
                startLocationX: 12,
                containerWidth: 390,
                layoutDirection: .leftToRight,
                translation: CGSize(width: 40, height: 8)
            ) == false
        )
    }

    @Test
    func safariBrowserNavigationRecognizesRTLLeadingEdgeBackSwipeAndRejectsVerticalDrag() {
        #expect(
            SafariBrowserNavigationState.shouldDismissSafariOnDrag(
                startLocationX: 378,
                containerWidth: 390,
                layoutDirection: .rightToLeft,
                translation: CGSize(width: -96, height: 8)
            )
        )
        #expect(
            SafariBrowserNavigationState.shouldDismissSafariOnDrag(
                startLocationX: 12,
                containerWidth: 390,
                layoutDirection: .rightToLeft,
                translation: CGSize(width: -96, height: 8)
            ) == false
        )
        #expect(
            SafariBrowserNavigationState.shouldDismissSafariOnDrag(
                startLocationX: 378,
                containerWidth: 390,
                layoutDirection: .rightToLeft,
                translation: CGSize(width: -96, height: 72)
            ) == false
        )
    }

    @Test
    func safariBrowserNavigationTracksLTRDismissalProgress() {
        #expect(
            SafariBrowserNavigationState.dismissalProgress(
                containerWidth: 400,
                layoutDirection: .leftToRight,
                translation: CGSize(width: 200, height: 8)
            ) == 0.5
        )
        #expect(
            SafariBrowserNavigationState.dismissalProgress(
                containerWidth: 400,
                layoutDirection: .leftToRight,
                translation: CGSize(width: -100, height: 8)
            ) == 0
        )
        #expect(
            SafariBrowserNavigationState.dismissalProgress(
                containerWidth: 400,
                layoutDirection: .leftToRight,
                translation: CGSize(width: 200, height: 72)
            ) == 0
        )
    }

    @Test
    func safariBrowserNavigationTracksRTLDismissalProgress() {
        #expect(
            SafariBrowserNavigationState.dismissalProgress(
                containerWidth: 400,
                layoutDirection: .rightToLeft,
                translation: CGSize(width: -200, height: 8)
            ) == 0.5
        )
        #expect(
            SafariBrowserNavigationState.dismissalProgress(
                containerWidth: 400,
                layoutDirection: .rightToLeft,
                translation: CGSize(width: 100, height: 8)
            ) == 0
        )
    }
}
