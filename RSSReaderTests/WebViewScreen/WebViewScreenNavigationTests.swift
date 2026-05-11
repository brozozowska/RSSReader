import Foundation
import Testing
@testable import RSSReader

@Suite("Safari Browser / Navigation")
@MainActor
struct WebViewScreenNavigationTests {
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
}
