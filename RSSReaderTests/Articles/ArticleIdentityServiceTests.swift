import Foundation
import Testing
@testable import RSSReader

@Suite("Articles / Identity Service")
struct ArticleIdentityServiceTests {
    @Test
    func externalIDUsesGuidBeforeCanonicalAndArticleURLs() {
        let externalID = ArticleIdentityService.makeExternalID(
            from: ArticleIdentityInput(
                feedURL: "HTTPS://Feeds.Example.com:443/rss.xml#fragment",
                guid: "  GUID-123  ",
                canonicalURL: "https://example.com/canonical",
                articleURL: "https://example.com/article",
                title: "Example Title",
                publishedAt: makeDate()
            )
        )

        #expect(externalID == "guid|https://feeds.example.com/rss.xml|GUID-123")
    }

    @Test
    func externalIDUsesCanonicalURLBeforeArticleURLWhenGuidIsMissing() {
        let externalID = ArticleIdentityService.makeExternalID(
            from: ArticleIdentityInput(
                feedURL: "https://feeds.example.com/rss.xml",
                guid: "   ",
                canonicalURL: " HTTPS://Example.COM:443/Articles/One?A=1#comments ",
                articleURL: "https://example.com/articles/fallback",
                title: "Example Title"
            )
        )

        #expect(externalID == "canonical-url|https://feeds.example.com/rss.xml|https://example.com/articles/one?a=1")
    }

    @Test
    func externalIDUsesArticleURLWhenGuidAndCanonicalURLAreMissing() {
        let externalID = ArticleIdentityService.makeExternalID(
            from: ArticleIdentityInput(
                feedURL: "https://feeds.example.com/rss.xml",
                guid: nil,
                canonicalURL: nil,
                articleURL: " HTTP://Example.COM:80/Articles/Two#read-later ",
                title: "Example Title"
            )
        )

        #expect(externalID == "article-url|https://feeds.example.com/rss.xml|http://example.com/articles/two")
    }

    @Test
    func fallbackExternalIDNormalizesFeedURLTitleWhitespaceAndDate() {
        let firstID = ArticleIdentityService.makeExternalID(
            from: ArticleIdentityInput(
                feedURL: "HTTPS://Feeds.Example.com:443/rss.xml#ignored",
                title: "  Important \n Article\tTitle  ",
                publishedAt: makeDate()
            )
        )
        let equivalentID = ArticleIdentityService.makeExternalID(
            from: ArticleIdentityInput(
                feedURL: "https://feeds.example.com/rss.xml",
                title: "important article title",
                publishedAt: makeDate()
            )
        )

        #expect(firstID == equivalentID)
        #expect(firstID.hasPrefix("fallback|"))
        #expect(firstID.dropFirst("fallback|".count).count == 64)
    }

    @Test
    func fallbackExternalIDChangesWhenNormalizedDateChanges() {
        let datedID = ArticleIdentityService.makeExternalID(
            from: ArticleIdentityInput(
                feedURL: "https://feeds.example.com/rss.xml",
                title: "Example Title",
                publishedAt: makeDate()
            )
        )
        let differentDateID = ArticleIdentityService.makeExternalID(
            from: ArticleIdentityInput(
                feedURL: "https://feeds.example.com/rss.xml",
                title: "Example Title",
                publishedAt: makeDate(hour: 11)
            )
        )
        let missingDateID = ArticleIdentityService.makeExternalID(
            from: ArticleIdentityInput(
                feedURL: "https://feeds.example.com/rss.xml",
                title: "Example Title",
                publishedAt: nil
            )
        )

        #expect(datedID != differentDateID)
        #expect(datedID != missingDateID)
        #expect(differentDateID != missingDateID)
    }

    @Test
    func equivalentURLInputsProduceStableExternalIDs() {
        let firstID = ArticleIdentityService.makeExternalID(
            from: ArticleIdentityInput(
                feedURL: "HTTPS://Feeds.Example.com:443/rss.xml",
                canonicalURL: "HTTPS://Example.COM:443/Article#comments",
                articleURL: "https://example.com/ignored",
                title: "Example Title"
            )
        )
        let equivalentID = ArticleIdentityService.makeExternalID(
            from: ArticleIdentityInput(
                feedURL: "https://feeds.example.com/rss.xml",
                canonicalURL: "https://example.com/article",
                articleURL: nil,
                title: "Other title does not affect canonical identity"
            )
        )

        #expect(firstID == equivalentID)
    }

    private func makeDate(hour: Int = 10) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = 2024
        components.month = 1
        components.day = 2
        components.hour = hour
        components.minute = 15
        components.second = 30
        components.nanosecond = 123_000_000

        return components.date ?? Date(timeIntervalSince1970: 0)
    }
}
