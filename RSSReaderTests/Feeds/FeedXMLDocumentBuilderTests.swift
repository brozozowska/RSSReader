import Foundation
import Testing
@testable import RSSReader

@Suite("Feeds / XML Document Builder")
struct FeedXMLDocumentBuilderTests {
    @Test
    func emptyDocumentThrowsEmptyDocumentError() {
        assertEmptyDocumentError(for: Data())
        assertEmptyDocumentError(for: makeData("   \n\t  "))
    }

    @Test
    func malformedXMLReportsLineColumnAndParserMessage() {
        let xml = """
        <rss>
          <channel>
        </rss>
        """

        do {
            _ = try FeedParserService.parse(makeData(xml))
            Issue.record("Expected malformed XML to throw")
        } catch FeedParserError.malformedXML(let line, let column, let message) {
            #expect(line > 0)
            #expect(column > 0)
            #expect(message.isEmpty == false)
        } catch {
            Issue.record("Expected malformed XML error, got \(error)")
        }
    }

    @Test
    func buildsElementTreeWithCDATAAttributesNamespacesAndQualifiedNames() throws {
        let document = try FeedParserService.parse(makeData(xmlWithNamespacesAndCDATA))
        let root = document.rootElement

        #expect(root.name == "rss")
        #expect(root.attributes["version"] == "2.0")

        let channel = try #require(root.firstChild(named: "channel"))
        #expect(channel.attributes["data-source"] == "fixture")
        #expect(channel.firstChildText(named: "title") == "Example <Feed>")
        #expect(channel.nestedChildText(["image", "url"]) == "https://example.com/icon.png")

        let item = try #require(channel.firstChild(named: "item"))
        #expect(item.attributes["id"] == "article-1")

        let creator = try #require(item.firstChild(named: "creator"))
        #expect(creator.qualifiedName == "dc:creator")
        #expect(creator.namespaceURI == "http://purl.org/dc/elements/1.1/")
        #expect(creator.normalizedText == "Author Name")

        let encodedContent = try #require(item.firstChild(named: "encoded"))
        #expect(encodedContent.qualifiedName == "content:encoded")
        #expect(encodedContent.namespaceURI == "http://purl.org/rss/1.0/modules/content/")
        #expect(encodedContent.normalizedText == "<p>HTML body</p>")
    }

    @Test
    func childLookupReturnsFirstMatchingChildAndAllMatchingChildren() throws {
        let document = try FeedParserService.parse(makeData(xmlWithNamespacesAndCDATA))
        let channel = try #require(document.rootElement.firstChild(named: "channel"))

        #expect(channel.firstChild(named: "item")?.attributes["id"] == "article-1")
        #expect(channel.children(named: "item").map(\.attributes["id"]) == ["article-1", "article-2"])
        #expect(channel.firstChildText(named: "missing") == nil)
        #expect(channel.nestedChildText(["image", "missing"]) == nil)
    }

    private var xmlWithNamespacesAndCDATA: String {
        """
        <rss
            xmlns:content="http://purl.org/rss/1.0/modules/content/"
            xmlns:dc="http://purl.org/dc/elements/1.1/"
            version="2.0">
          <channel data-source="fixture">
            <title><![CDATA[Example <Feed>]]></title>
            <image>
              <url> https://example.com/icon.png </url>
            </image>
            <item id="article-1">
              <dc:creator>Author Name</dc:creator>
              <content:encoded><![CDATA[<p>HTML body</p>]]></content:encoded>
            </item>
            <item id="article-2">
              <title>Second Article</title>
            </item>
          </channel>
        </rss>
        """
    }

    private func makeData(_ xml: String) -> Data {
        Data(xml.utf8)
    }

    private func assertEmptyDocumentError(for data: Data) {
        do {
            _ = try FeedParserService.parse(data)
            Issue.record("Expected empty document to throw")
        } catch FeedParserError.emptyDocument {
            return
        } catch {
            Issue.record("Expected empty document error, got \(error)")
        }
    }
}
