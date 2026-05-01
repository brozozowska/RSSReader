import Testing
@testable import RSSReader

@Suite("Infrastructure / RSSReaderApp")
struct RSSReaderAppTests {
    @Test
    func rssReaderAppUsesBackgroundRefreshIdentifierFromInfrastructureConfiguration() {
        #expect(
            RSSReaderApp.backgroundAppRefreshIdentifier
                == BackgroundRefreshTaskConfiguration.appRefreshIdentifier
        )
    }
}
