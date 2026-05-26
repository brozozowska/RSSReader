import Foundation
import Testing
@testable import RSSReader

@Suite("Feeds / Normalization")
@MainActor
struct FeedNormalizationTests {
    @Test
    func feedNormalizationKeepsFaviconLikeIconURLAndNormalizesIt() {
        let feed = ParsedFeedDTO(
            kind: .rss,
            metadata: ParsedFeedMetadataDTO(
                title: "Example Feed",
                siteURL: "HTTPS://Example.com",
                iconURL: "HTTPS://CDN.EXAMPLE.COM/Favicon-32x32.png?cache=1#fragment"
            ),
            entries: []
        )

        let normalized = FeedNormalizationService.normalize(feed, feedURL: "https://example.com/feed.xml")

        #expect(normalized.metadata.siteURL == "https://example.com/")
        #expect(normalized.metadata.iconURL == "https://cdn.example.com/Favicon-32x32.png?cache=1")
    }

    @Test
    func feedNormalizationRewritesLogoAssetToSiteFaviconWhenSiteURLIsKnown() {
        let feed = ParsedFeedDTO(
            kind: .rss,
            metadata: ParsedFeedMetadataDTO(
                title: "Example Feed",
                siteURL: "https://example.com/news/",
                iconURL: "https://cdn.example.com/assets/header-banner.png"
            ),
            entries: []
        )

        let normalized = FeedNormalizationService.normalize(feed, feedURL: "https://example.com/feed.xml")

        #expect(normalized.metadata.iconURL == "https://example.com/favicon.ico")
    }

    @Test
    func feedNormalizationRewritesBannerAssetToFeedOriginFaviconWhenSiteURLIsMissing() {
        let feed = ParsedFeedDTO(
            kind: .atom,
            metadata: ParsedFeedMetadataDTO(
                title: "Example Feed",
                iconURL: "https://cdn.example.com/assets/banner.png"
            ),
            entries: []
        )

        let normalized = FeedNormalizationService.normalize(feed, feedURL: "https://example.com/feed.xml")

        #expect(normalized.metadata.iconURL == "https://example.com/favicon.ico")
    }

    @Test
    func feedNormalizationUsesSiteFaviconWhenFeedDidNotProvideIconURL() {
        let feed = ParsedFeedDTO(
            kind: .rss,
            metadata: ParsedFeedMetadataDTO(
                title: "Example Feed",
                siteURL: "HTTPS://Example.com/news"
            ),
            entries: []
        )

        let normalized = FeedNormalizationService.normalize(feed, feedURL: "https://example.com/feed.xml")

        #expect(normalized.metadata.siteURL == "https://example.com/news")
        #expect(normalized.metadata.iconURL == "https://example.com/favicon.ico")
    }

    @Test
    func feedNormalizationResolvesRelativeFeedIconURLAgainstSiteURL() {
        let feed = ParsedFeedDTO(
            kind: .atom,
            metadata: ParsedFeedMetadataDTO(
                title: "Example Feed",
                siteURL: "https://example.com/news/",
                iconURL: "/assets/source-icon-64x64.png"
            ),
            entries: []
        )

        let normalized = FeedNormalizationService.normalize(feed, feedURL: "https://example.com/feed.xml")

        #expect(normalized.metadata.iconURL == "https://example.com/assets/source-icon-64x64.png")
    }

    @Test
    func feedNormalizationUsesFeedOriginFaviconWhenFeedDidNotProvideSiteURLOrIconURL() {
        let feed = ParsedFeedDTO(
            kind: .rss,
            metadata: ParsedFeedMetadataDTO(
                title: "Example Feed"
            ),
            entries: []
        )

        let normalized = FeedNormalizationService.normalize(feed, feedURL: "https://feeds.example.com/rss.xml")

        #expect(normalized.metadata.iconURL == "https://feeds.example.com/favicon.ico")
    }

    @Test
    func feedNormalizationKeepsExplicitRSSImageLogoFromNPlusOne() {
        let feed = ParsedFeedDTO(
            kind: .rss,
            metadata: ParsedFeedMetadataDTO(
                title: "N + 1 — главное издание о науке, технике и технологиях",
                siteURL: "https://nplus1.ru/rss",
                iconURL: "https://staticn1.nplus1.ru/image-new/logo.png"
            ),
            entries: []
        )

        let normalized = FeedNormalizationService.normalize(feed, feedURL: "https://nplus1.ru/rss")

        #expect(normalized.metadata.iconURL == "https://staticn1.nplus1.ru/image-new/logo.png")
    }

    @Test
    func feedNormalizationKeepsExplicitRSSImageLogoFromTJForRuntimeShapeValidation() {
        let feed = ParsedFeedDTO(
            kind: .rss,
            metadata: ParsedFeedMetadataDTO(
                title: "Т—Ж",
                siteURL: "https://t-j.ru/",
                iconURL: "https://static2.tinkoffjournal.ru/mercury-old/img/core-logo-rss.png"
            ),
            entries: []
        )

        let normalized = FeedNormalizationService.normalize(feed, feedURL: "https://t-j.ru/feed")

        #expect(normalized.metadata.iconURL == "https://static2.tinkoffjournal.ru/mercury-old/img/core-logo-rss.png")
    }

    @Test
    func feedNormalizationRemovesEmailFromEntryAuthor() {
        let feed = ParsedFeedDTO(
            kind: .rss,
            metadata: ParsedFeedMetadataDTO(title: "N + 1"),
            entries: [
                ParsedFeedEntryDTO(
                    guid: "https://nplus1.ru/news/2026/05/25/subduction-and-oxygenation",
                    url: "https://nplus1.ru/news/2026/05/25/subduction-and-oxygenation",
                    title: "«Холодная» субдукция оказалась выгодна для накопления кислорода в атмосфере",
                    author: """
                    Винера Андреева            <v.and73@gmail.com>
                    """,
                    publishedAtRaw: "Mon, 25 May 2026 22:00:00 +0300"
                )
            ]
        )

        let normalized = FeedNormalizationService.normalize(feed, feedURL: "https://nplus1.ru/rss")

        #expect(normalized.entries.first?.author == "Винера Андреева")
    }

    @Test(arguments: [
        "Сергей Коленов <sergey-k-0@yandex.ru>",
        "Сергей Коленов (sergey-k-0@yandex.ru)",
        "Сергей Коленов [sergey-k-0@yandex.ru]",
        "Сергей Коленов mailto:sergey-k-0@yandex.ru",
        "Сергей Коленов <mailto:sergey-k-0@yandex.ru>"
    ])
    func feedNormalizationRemovesCommonEmailShapesFromEntryAuthor(author: String) {
        let feed = ParsedFeedDTO(
            kind: .rss,
            metadata: ParsedFeedMetadataDTO(title: "N + 1"),
            entries: [
                ParsedFeedEntryDTO(
                    url: "https://nplus1.ru/news/example",
                    title: "Example",
                    author: author
                )
            ]
        )

        let normalized = FeedNormalizationService.normalize(feed, feedURL: "https://nplus1.ru/rss")

        #expect(normalized.entries.first?.author == "Сергей Коленов")
    }
}
