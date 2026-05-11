import SafariServices
import Testing
@testable import RSSReader

@Suite("Safari / Presentation")
@MainActor
struct SafariPresentationTests {
    @Test
    func safariPresentationUsesStandardBrowserChromeConfiguration() {
        let configuration = ArticleSafariPresentationConfiguration.standard

        #expect(configuration.dismissButtonStyle == .close)
        #expect(configuration.barCollapsingEnabled)
    }

    @Test
    func articleSafariRouteAllowsOnlyHTTPAndHTTPSURLsWithHosts() {
        #expect(ArticleSafariRoute.canOpen(URL(string: "https://example.com/article")!))
        #expect(ArticleSafariRoute.canOpen(URL(string: "http://example.com/article")!))
        #expect(ArticleSafariRoute.canOpen(URL(string: "mailto:hello@example.com")!) == false)
        #expect(ArticleSafariRoute.canOpen(URL(string: "ftp://example.com/article")!) == false)
        #expect(ArticleSafariRoute.canOpen(URL(string: "https:///article")!) == false)
    }
}
