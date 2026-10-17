import Foundation
import Testing
@testable import RSSReader

@Suite("Feeds / RSS Parser")
struct FeedRSSParserTests {
    @Test
    func parsesRSSChannelMetadataAndItemPayloadsFromFixture() throws {
        let parsedFeed = try FeedParserService.parseRSS(parseDocument(rssFixture))

        #expect(parsedFeed.kind == .rss)
        #expect(parsedFeed.metadata.title == "Example RSS Feed")
        #expect(parsedFeed.metadata.subtitle == "Readable feed description")
        #expect(parsedFeed.metadata.siteURL == "https://example.com/")
        #expect(parsedFeed.metadata.iconURL == "https://example.com/rss-icon.png")
        #expect(parsedFeed.metadata.language == "en")

        #expect(parsedFeed.entries.count == 2)

        let firstEntry = try #require(parsedFeed.entries.first)
        #expect(firstEntry.guid == "article-1")
        #expect(firstEntry.url == "https://example.com/articles/1")
        #expect(firstEntry.canonicalURL == "https://example.com/articles/1#comments")
        #expect(firstEntry.title == "First Article")
        #expect(firstEntry.summary == "Short first summary")
        #expect(firstEntry.contentHTML == "<p>Full first article body</p>")
        #expect(firstEntry.contentText == "Short first summary")
        #expect(firstEntry.author == "Author One")
        #expect(firstEntry.publishedAtRaw == "Tue, 02 Jan 2024 10:15:30 +0000")
        #expect(firstEntry.updatedAtRaw == "Tue, 02 Jan 2024 11:00:00 +0000")
        #expect(firstEntry.imageURL == "https://example.com/images/first.jpg")

        let secondEntry = try #require(parsedFeed.entries.dropFirst().first)
        #expect(secondEntry.guid == "article-2")
        #expect(secondEntry.title == "Second Article")
        #expect(secondEntry.contentHTML == "Fallback encoded body")
        #expect(secondEntry.author == "Fallback Creator")
        #expect(secondEntry.imageURL == nil)
    }

    @Test
    func missingChannelThrowsMissingRSSElementDiagnostic() throws {
        let document = try parseDocument("""
        <rss version="2.0">
          <item>
            <title>Orphan Item</title>
          </item>
        </rss>
        """)

        do {
            _ = try FeedParserService.parseRSS(document)
            Issue.record("Expected missing channel to throw")
        } catch FeedParserError.missingRSSElement(let elementName) {
            #expect(elementName == "channel")
        } catch {
            Issue.record("Expected missing RSS element error, got \(error)")
        }
    }

    @Test
    func mapsQualifiedDublinCoreDatesBySemanticRoleAndCoreRSSPrecedence() throws {
        let document = try parseDocument("""
        <rss
            xmlns:dc="http://purl.org/dc/elements/1.1/"
            xmlns:dcterms="http://purl.org/dc/terms/"
            xmlns:foreign="https://example.com/date-extension"
            version="2.0">
          <channel>
            <title>Dublin Core dates</title>
            <link>https://example.com/</link>
            <lastBuildDate>Tue, 09 Jan 2024 12:00:00 GMT</lastBuildDate>
            <item>
              <title>Core RSS wins publication conflicts</title>
              <link>https://example.com/articles/core</link>
              <pubDate>Tue, 02 Jan 2024 10:15:30 GMT</pubDate>
              <dc:date>2024-01-01</dc:date>
              <dcterms:created>2023-12-31</dcterms:created>
              <dcterms:modified>2024-01-03T12:30:00Z</dcterms:modified>
            </item>
            <item>
              <title>Qualified creation fallback</title>
              <link>https://example.com/articles/created</link>
              <dcterms:created>2024-01-04</dcterms:created>
              <dc:date>2024-01-03</dc:date>
            </item>
            <item>
              <title>Generic Dublin Core fallback</title>
              <link>https://example.com/articles/dc-date</link>
              <dc:date>2024-01-05</dc:date>
            </item>
            <item>
              <title>Foreign date is not source metadata</title>
              <link>https://example.com/articles/foreign</link>
              <foreign:date>2024-01-06</foreign:date>
            </item>
          </channel>
        </rss>
        """)

        let entries = try FeedParserService.parseRSS(document).entries

        #expect(entries[0].publishedAtRaw == "Tue, 02 Jan 2024 10:15:30 GMT")
        #expect(entries[0].updatedAtRaw == "2024-01-03T12:30:00Z")
        #expect(entries[1].publishedAtRaw == "2024-01-04")
        #expect(entries[1].updatedAtRaw == nil)
        #expect(entries[2].publishedAtRaw == "2024-01-05")
        #expect(entries[3].publishedAtRaw == nil)
        #expect(entries[3].updatedAtRaw == nil)
    }

    private var rssFixture: String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss
            xmlns:content="http://purl.org/rss/1.0/modules/content/"
            xmlns:dc="http://purl.org/dc/elements/1.1/"
            xmlns:dcterms="http://purl.org/dc/terms/"
            version="2.0">
          <channel>
            <title>Example RSS Feed</title>
            <link>https://example.com/</link>
            <description>Readable feed description</description>
            <language>en</language>
            <image>
              <url>https://example.com/rss-icon.png</url>
            </image>
            <item>
              <guid isPermaLink="false">article-1</guid>
              <link>https://example.com/articles/1</link>
              <comments>https://example.com/articles/1#comments</comments>
              <title>First Article</title>
              <description>Short first summary</description>
              <content:encoded><![CDATA[<p>Full first article body</p>]]></content:encoded>
              <dc:creator>Author One</dc:creator>
              <pubDate>Tue, 02 Jan 2024 10:15:30 +0000</pubDate>
              <dcterms:modified>Tue, 02 Jan 2024 11:00:00 +0000</dcterms:modified>
              <enclosure url=" https://example.com/images/first.jpg " type="image/jpeg" />
            </item>
            <item>
              <guid>article-2</guid>
              <title>Second Article</title>
              <encoded>Fallback encoded body</encoded>
              <creator>Fallback Creator</creator>
            </item>
          </channel>
        </rss>
        """
    }

    private func parseDocument(_ xml: String) throws -> FeedXMLDocument {
        try FeedParserService.parse(Data(xml.utf8))
    }
}
