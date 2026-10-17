import Foundation
import Testing
@testable import RSSReader

@Suite("Feeds / Date Compatibility Matrix")
struct FeedDateCompatibilityMatrixTests {
    @Test
    func parsesSanitizedRealFeedDateProfiles() throws {
        for fixture in Self.realFeedFixtures {
            let result = try FeedParserService.parsePipelineResult(
                Data(fixture.xml.utf8),
                feedURL: fixture.feedURL
            )
            let entry = try #require(result.feed.entries.first, "\(fixture.name) entry")

            #expect(entry.publishedAtRaw == fixture.publishedAtRaw, "\(fixture.name) published raw")
            #expect(entry.updatedAtRaw == fixture.updatedAtRaw, "\(fixture.name) updated raw")
            #expect(Self.datesMatch(entry.publishedAt, fixture.publishedAt), "\(fixture.name) published date")
            #expect(Self.datesMatch(entry.updatedAt, fixture.updatedAt), "\(fixture.name) updated date")
            #expect(
                Self.datesMatch(entry.effectiveSourceDate, fixture.effectiveSourceDate),
                "\(fixture.name) effective date"
            )
            #expect(result.diagnostics.parserAnomalies.isEmpty, "\(fixture.name) diagnostics")
        }
    }

    @Test
    func normalizesDublinCoreCreatedModifiedAndGenericDateSemantics() throws {
        let result = try FeedParserService.parsePipelineResult(
            Data("""
            <rss
                xmlns:dc="http://purl.org/dc/elements/1.1/"
                xmlns:dcterms="http://purl.org/dc/terms/"
                version="2.0">
              <channel>
                <title>Dublin Core compatibility fixture</title>
                <link>https://example.com/</link>
                <item>
                  <guid>qualified-dublin-core</guid>
                  <title>Qualified Dublin Core dates</title>
                  <link>https://example.com/dublin/qualified</link>
                  <description>Sanitized standards-backed fixture.</description>
                  <dcterms:created>2024-01-02</dcterms:created>
                  <dcterms:modified>2024-01-03T11:20:35Z</dcterms:modified>
                </item>
                <item>
                  <guid>generic-dublin-core</guid>
                  <title>Generic Dublin Core date</title>
                  <link>https://example.com/dublin/generic</link>
                  <description>Sanitized standards-backed fixture.</description>
                  <dc:date>2024-01-04</dc:date>
                </item>
              </channel>
            </rss>
            """.utf8),
            feedURL: "https://example.com/dublin.rss"
        )
        let qualifiedEntry = try #require(result.feed.entries.first)
        let genericEntry = try #require(result.feed.entries.dropFirst().first)

        #expect(
            qualifiedEntry.publishedAt == Self.date(
                year: 2024,
                month: 1,
                day: 2,
                hour: 0,
                minute: 0,
                second: 0
            )
        )
        #expect(
            qualifiedEntry.updatedAt == Self.date(
                year: 2024,
                month: 1,
                day: 3,
                hour: 11,
                minute: 20,
                second: 35
            )
        )
        #expect(
            genericEntry.publishedAt == Self.date(
                year: 2024,
                month: 1,
                day: 4,
                hour: 0,
                minute: 0,
                second: 0
            )
        )
        #expect(genericEntry.updatedAt == nil)
    }

    @Test
    func publicationDateWinsEffectiveSourceDateWhenBothSemanticDatesExist() throws {
        let result = try FeedParserService.parsePipelineResult(
            Data(Self.redditLikeAtom.xml.utf8),
            feedURL: Self.redditLikeAtom.feedURL
        )
        let entry = try #require(result.feed.entries.first)

        #expect(entry.publishedAt != entry.updatedAt)
        #expect(entry.effectiveSourceDate == entry.publishedAt)
    }

    @Test
    func materializesSourceSemanticsWithoutSubstitutingFetchedAt() throws {
        let fetchedAt = Self.date(
            year: 2024,
            month: 2,
            day: 1,
            hour: 12,
            minute: 0,
            second: 0
        )
        let appleResult = try FeedParserService.parsePipelineResult(
            Data(Self.appleLikeAtom.xml.utf8),
            feedURL: Self.appleLikeAtom.feedURL
        )
        let redditResult = try FeedParserService.parsePipelineResult(
            Data(Self.redditLikeAtom.xml.utf8),
            feedURL: Self.redditLikeAtom.feedURL
        )
        let applePayload = try #require(
            ArticleUpsertPayload.makeAllPrepared(
                entries: appleResult.feed.entries,
                fetchedAt: fetchedAt
            ).first
        )
        let redditPayload = try #require(
            ArticleUpsertPayload.makeAllPrepared(
                entries: redditResult.feed.entries,
                fetchedAt: fetchedAt
            ).first
        )

        #expect(applePayload.publishedAt == nil)
        #expect(applePayload.updatedAtSource == appleResult.feed.entries.first?.updatedAt)
        #expect(applePayload.fetchedAt == fetchedAt)
        #expect(redditPayload.publishedAt == redditResult.feed.entries.first?.publishedAt)
        #expect(redditPayload.updatedAtSource == redditResult.feed.entries.first?.updatedAt)
        #expect(redditPayload.fetchedAt == fetchedAt)
    }

    @Test
    func ignoresForeignNamespaceDateElementsInsideAtomEntry() throws {
        let result = try FeedParserService.parsePipelineResult(
            Data("""
            <feed xmlns="http://www.w3.org/2005/Atom" xmlns:foreign="https://example.com/date-extension">
              <title>Namespace fixture</title>
              <link href="https://example.com/" />
              <updated>2024-01-10T12:00:00Z</updated>
              <entry>
                <id>namespace-date</id>
                <title>Atom namespace date</title>
                <link href="https://example.com/namespace-date" />
                <summary>Foreign dates must not override Atom dates.</summary>
                <foreign:published>2020-01-01T00:00:00Z</foreign:published>
                <foreign:updated>2020-01-02T00:00:00Z</foreign:updated>
                <published>2024-01-02T10:15:30Z</published>
                <updated>2024-01-03T11:20:35Z</updated>
              </entry>
            </feed>
            """.utf8),
            feedURL: "https://example.com/namespace.atom"
        )
        let entry = try #require(result.feed.entries.first)

        #expect(entry.publishedAtRaw == "2024-01-02T10:15:30Z")
        #expect(entry.updatedAtRaw == "2024-01-03T11:20:35Z")
    }

    @Test
    func reportsNonEmptyMalformedDatesWithoutReplacingThemWithFetchTime() throws {
        let result = try FeedParserService.parsePipelineResult(
            Data("""
            <feed xmlns="http://www.w3.org/2005/Atom">
              <title>Malformed date fixture</title>
              <link href="https://example.com/" />
              <updated>2024-01-10T12:00:00Z</updated>
              <entry>
                <id>malformed-date</id>
                <title>Malformed source dates</title>
                <link href="https://example.com/malformed" />
                <summary>Entry remains usable without a source date.</summary>
                <published>not-a-publication-date</published>
                <updated>2024-13-99T99:99:99Z</updated>
              </entry>
            </feed>
            """.utf8),
            feedURL: "https://example.com/malformed.atom"
        )
        let entry = try #require(result.feed.entries.first)
        let anomalyKinds = result.diagnostics.parserAnomalies.map(\.kind)

        #expect(entry.publishedAtRaw == "not-a-publication-date")
        #expect(entry.updatedAtRaw == "2024-13-99T99:99:99Z")
        #expect(entry.publishedAt == nil)
        #expect(entry.updatedAt == nil)
        #expect(entry.effectiveSourceDate == nil)
        #expect(anomalyKinds.contains(.entryUnrecognizedPublishedDate))
        #expect(anomalyKinds.contains(.entryUnrecognizedUpdatedDate))
        #expect(anomalyKinds.contains(.entryMissingDates) == false)
    }

    @Test
    func treatsWhitespaceDatesAsMissingRatherThanMalformed() throws {
        let result = try FeedParserService.parsePipelineResult(
            Data("""
            <rss version="2.0">
              <channel>
                <title>Whitespace date fixture</title>
                <link>https://example.com/</link>
                <item>
                  <guid>whitespace-date</guid>
                  <title>Whitespace source dates</title>
                  <link>https://example.com/whitespace</link>
                  <description>Whitespace should normalize away.</description>
                  <pubDate> \n\t </pubDate>
                </item>
              </channel>
            </rss>
            """.utf8),
            feedURL: "https://example.com/whitespace.rss"
        )
        let entry = try #require(result.feed.entries.first)
        let anomalyKinds = result.diagnostics.parserAnomalies.map(\.kind)

        #expect(entry.publishedAtRaw == nil)
        #expect(entry.updatedAtRaw == nil)
        #expect(anomalyKinds.contains(.entryMissingDates))
        #expect(anomalyKinds.contains(.entryUnrecognizedPublishedDate) == false)
        #expect(anomalyKinds.contains(.entryUnrecognizedUpdatedDate) == false)
    }

    @Test
    func doesNotPromoteFeedOrChannelTimestampsToEntryDates() throws {
        let atomResult = try FeedParserService.parsePipelineResult(
            Data("""
            <feed xmlns="http://www.w3.org/2005/Atom">
              <title>Container-only Atom date</title>
              <link href="https://example.com/" />
              <updated>2024-01-10T12:00:00Z</updated>
              <entry>
                <id>atom-without-entry-date</id>
                <title>Undated Atom entry</title>
                <link href="https://example.com/atom-undated" />
                <summary>No entry-level date.</summary>
              </entry>
            </feed>
            """.utf8),
            feedURL: "https://example.com/container.atom"
        )
        let rssResult = try FeedParserService.parsePipelineResult(
            Data("""
            <rss version="2.0">
              <channel>
                <title>Container-only RSS date</title>
                <link>https://example.com/</link>
                <lastBuildDate>Tue, 02 Jan 2024 10:15:30 GMT</lastBuildDate>
                <item>
                  <guid>rss-without-item-date</guid>
                  <title>Undated RSS item</title>
                  <link>https://example.com/rss-undated</link>
                  <description>No item-level date.</description>
                </item>
              </channel>
            </rss>
            """.utf8),
            feedURL: "https://example.com/container.rss"
        )

        let atomEntry = try #require(atomResult.feed.entries.first)
        let rssEntry = try #require(rssResult.feed.entries.first)
        #expect(atomEntry.effectiveSourceDate == nil)
        #expect(rssEntry.effectiveSourceDate == nil)
        #expect(atomResult.diagnostics.parserAnomalies.map(\.kind).contains(.entryMissingDates))
        #expect(rssResult.diagnostics.parserAnomalies.map(\.kind).contains(.entryMissingDates))
    }

    private struct Fixture {
        let name: String
        let feedURL: String
        let xml: String
        let publishedAtRaw: String?
        let updatedAtRaw: String?
        let publishedAt: Date?
        let updatedAt: Date?

        var effectiveSourceDate: Date? {
            publishedAt ?? updatedAt
        }
    }

    private static func datesMatch(_ lhs: Date?, _ rhs: Date?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            true
        case let (lhs?, rhs?):
            abs(lhs.timeIntervalSince(rhs)) < 0.001
        default:
            false
        }
    }

    private static let appleLikeAtom = Fixture(
        name: "Apple Newsroom Atom updated-only with fractional seconds",
        feedURL: "https://www.apple.com/newsroom/rss-feed.rss",
        xml: atomFixture(
            title: "Apple-like entry",
            identifier: "apple-like",
            published: nil,
            updated: "2024-01-02T10:15:30.486Z"
        ),
        publishedAtRaw: nil,
        updatedAtRaw: "2024-01-02T10:15:30.486Z",
        publishedAt: nil,
        updatedAt: date(year: 2024, month: 1, day: 2, hour: 10, minute: 15, second: 30, nanosecond: 486_000_000)
    )

    private static let swiftLikeAtom = Fixture(
        name: "Swift.org Atom updated-only with numeric offset",
        feedURL: "https://www.swift.org/atom.xml",
        xml: atomFixture(
            title: "Swift-like entry",
            identifier: "swift-like",
            published: nil,
            updated: "2024-01-02T06:15:30-04:00"
        ),
        publishedAtRaw: nil,
        updatedAtRaw: "2024-01-02T06:15:30-04:00",
        publishedAt: nil,
        updatedAt: date(year: 2024, month: 1, day: 2, hour: 10, minute: 15, second: 30)
    )

    private static let redditLikeAtom = Fixture(
        name: "Reddit Atom published and updated",
        feedURL: "https://www.reddit.com/r/swift/.rss",
        xml: atomFixture(
            title: "Reddit-like entry",
            identifier: "reddit-like",
            published: "2024-01-02T10:15:30+00:00",
            updated: "2024-01-03T11:20:35+00:00"
        ),
        publishedAtRaw: "2024-01-02T10:15:30+00:00",
        updatedAtRaw: "2024-01-03T11:20:35+00:00",
        publishedAt: date(year: 2024, month: 1, day: 2, hour: 10, minute: 15, second: 30),
        updatedAt: date(year: 2024, month: 1, day: 3, hour: 11, minute: 20, second: 35)
    )

    private static let bbcLikeRSS = Fixture(
        name: "BBC RSS pubDate with GMT zone",
        feedURL: "https://feeds.bbci.co.uk/news/rss.xml",
        xml: rssFixture(
            title: "BBC-like item",
            identifier: "bbc-like",
            publicationDate: "Tue, 02 Jan 2024 10:15:30 GMT"
        ),
        publishedAtRaw: "Tue, 02 Jan 2024 10:15:30 GMT",
        updatedAtRaw: nil,
        publishedAt: date(year: 2024, month: 1, day: 2, hour: 10, minute: 15, second: 30),
        updatedAt: nil
    )

    private static let wordpressLikeRSS = Fixture(
        name: "WordPress RSS pubDate with numeric zone",
        feedURL: "https://wordpress.org/news/feed/",
        xml: rssFixture(
            title: "WordPress-like item",
            identifier: "wordpress-like",
            publicationDate: "Tue, 02 Jan 2024 13:15:30 +0300"
        ),
        publishedAtRaw: "Tue, 02 Jan 2024 13:15:30 +0300",
        updatedAtRaw: nil,
        publishedAt: date(year: 2024, month: 1, day: 2, hour: 10, minute: 15, second: 30),
        updatedAt: nil
    )

    private static let realFeedFixtures = [
        appleLikeAtom,
        swiftLikeAtom,
        redditLikeAtom,
        bbcLikeRSS,
        wordpressLikeRSS
    ]

    private static func atomFixture(
        title: String,
        identifier: String,
        published: String?,
        updated: String
    ) -> String {
        let publishedElement = published.map { "<published>\($0)</published>" } ?? ""
        return """
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>Sanitized compatibility fixture</title>
          <link href="https://example.com/" />
          <updated>2024-01-10T12:00:00Z</updated>
          <entry>
            <id>\(identifier)</id>
            <title>\(title)</title>
            <link href="https://example.com/articles/\(identifier)" />
            <summary>Sanitized source-shape fixture.</summary>
            \(publishedElement)
            <updated>\(updated)</updated>
          </entry>
        </feed>
        """
    }

    private static func rssFixture(
        title: String,
        identifier: String,
        publicationDate: String
    ) -> String {
        """
        <rss version="2.0">
          <channel>
            <title>Sanitized compatibility fixture</title>
            <link>https://example.com/</link>
            <lastBuildDate>Tue, 09 Jan 2024 12:00:00 GMT</lastBuildDate>
            <item>
              <guid>\(identifier)</guid>
              <title>\(title)</title>
              <link>https://example.com/articles/\(identifier)</link>
              <description>Sanitized source-shape fixture.</description>
              <pubDate>\(publicationDate)</pubDate>
            </item>
          </channel>
        </rss>
        """
    }

    private static func date(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        second: Int,
        nanosecond: Int = 0
    ) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        components.nanosecond = nanosecond
        return components.date ?? .distantPast
    }
}
