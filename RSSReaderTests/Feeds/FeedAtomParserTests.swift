import Foundation
import Testing
@testable import RSSReader

@Suite("Feeds / Atom Parser")
struct FeedAtomParserTests {
    @Test
    func parsesAtomMetadataEntryPayloadsAndLinksFromFixture() throws {
        let parsedFeed = try FeedParserService.parseAtom(parseDocument(atomFixture))

        #expect(parsedFeed.kind == .atom)
        #expect(parsedFeed.metadata.title == "Example Atom Feed")
        #expect(parsedFeed.metadata.subtitle == "Readable Atom subtitle")
        #expect(parsedFeed.metadata.siteURL == "https://example.com/")
        #expect(parsedFeed.metadata.iconURL == "https://example.com/icon.png")
        #expect(parsedFeed.metadata.language == "en")

        #expect(parsedFeed.entries.count == 2)

        let firstEntry = try #require(parsedFeed.entries.first)
        #expect(firstEntry.guid == "tag:example.com,2024:first")
        #expect(firstEntry.url == "https://example.com/articles/1")
        #expect(firstEntry.canonicalURL == "https://example.com/feed/entries/1")
        #expect(firstEntry.title == "First Atom Article")
        #expect(firstEntry.summary == "Short Atom summary")
        #expect(firstEntry.contentHTML == "<p>Full Atom body</p>")
        #expect(firstEntry.contentText == "<p>Full Atom body</p>")
        #expect(firstEntry.author == "Entry Author")
        #expect(firstEntry.publishedAtRaw == "2024-01-02T10:15:30Z")
        #expect(firstEntry.updatedAtRaw == "2024-01-02T11:00:00Z")
        #expect(firstEntry.imageURL == "https://example.com/images/atom-first.jpg")

        let secondEntry = try #require(parsedFeed.entries.dropFirst().first)
        #expect(secondEntry.guid == "tag:example.com,2024:second")
        #expect(secondEntry.url == "https://example.com/articles/2")
        #expect(secondEntry.canonicalURL == "https://example.com/feed/entries/2")
        #expect(secondEntry.title == "Second Atom Article")
        #expect(secondEntry.summary == "Only summary body")
        #expect(secondEntry.contentHTML == "Only summary body")
        #expect(secondEntry.contentText == "Only summary body")
        #expect(secondEntry.author == "Feed Author")
        #expect(secondEntry.imageURL == nil)
    }

    @Test
    func missingFeedRootThrowsMissingAtomElementDiagnostic() throws {
        let document = try parseDocument("""
        <source xmlns="http://www.w3.org/2005/atom">
          <title>Atom-like root without feed</title>
        </source>
        """)

        do {
            _ = try FeedParserService.extractAtomMetadata(from: document)
            Issue.record("Expected missing feed to throw")
        } catch FeedParserError.missingAtomElement(let elementName) {
            #expect(elementName == "feed")
        } catch {
            Issue.record("Expected missing Atom element error, got \(error)")
        }
    }

    private var atomFixture: String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/atom" xml:lang="en">
          <title>Example Atom Feed</title>
          <subtitle>Readable Atom subtitle</subtitle>
          <link rel="self" href="https://example.com/feed.atom" />
          <link rel="alternate" href=" https://example.com/ " />
          <icon>https://example.com/icon.png</icon>
          <author>
            <name>Feed Author</name>
          </author>
          <entry>
            <id>tag:example.com,2024:first</id>
            <title>First Atom Article</title>
            <link rel="alternate" href="https://example.com/articles/1" />
            <link rel="self" href="https://example.com/feed/entries/1" />
            <link rel="enclosure" type="image/jpeg" href=" https://example.com/images/atom-first.jpg " />
            <summary>Short Atom summary</summary>
            <content type="html"><![CDATA[<p>Full Atom body</p>]]></content>
            <author>
              <name>Entry Author</name>
            </author>
            <published>2024-01-02T10:15:30Z</published>
            <updated>2024-01-02T11:00:00Z</updated>
          </entry>
          <entry>
            <id>tag:example.com,2024:second</id>
            <title>Second Atom Article</title>
            <link href="https://example.com/articles/2" />
            <link rel="self" href="https://example.com/feed/entries/2" />
            <summary>Only summary body</summary>
          </entry>
        </feed>
        """
    }

    private func parseDocument(_ xml: String) throws -> FeedXMLDocument {
        try FeedParserService.parse(Data(xml.utf8))
    }
}
