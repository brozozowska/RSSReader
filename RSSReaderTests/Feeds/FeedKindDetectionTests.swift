import Foundation
import Testing
@testable import RSSReader

@Suite("Feeds / Kind Detection")
struct FeedKindDetectionTests {
    @Test
    func detectsRSSFeedFromRootElementName() throws {
        let document = try FeedParserService.parse(makeData("""
        <rss version="2.0">
          <channel />
        </rss>
        """))

        #expect(FeedParserService.detectFeedKind(in: document) == .rss)
        #expect(document.detectedFeedKind == .rss)
    }

    @Test
    func detectsAtomFeedFromRootNameAndNamespace() throws {
        let document = try FeedParserService.parse(makeData("""
        <feed xmlns="http://www.w3.org/2005/atom">
          <title>Example Atom Feed</title>
        </feed>
        """))

        #expect(FeedParserService.detectFeedKind(in: document) == .atom)
        #expect(document.detectedFeedKind == .atom)
    }

    @Test
    func detectsNamespaceQualifiedFeeds() throws {
        let qualifiedRSSDocument = try FeedParserService.parse(makeData("""
        <rss:rss xmlns:rss="https://www.rssboard.org/rss-specification" version="2.0">
          <rss:channel />
        </rss:rss>
        """))
        let qualifiedAtomDocument = try FeedParserService.parse(makeData("""
        <atom:feed xmlns:atom="http://www.w3.org/2005/atom">
          <atom:title>Example Atom Feed</atom:title>
        </atom:feed>
        """))

        #expect(FeedParserService.detectFeedKind(in: qualifiedRSSDocument) == .rss)
        #expect(FeedParserService.detectFeedKind(in: qualifiedAtomDocument) == .atom)
    }

    @Test
    func returnsUnknownForUnsupportedRootElements() throws {
        let document = try FeedParserService.parse(makeData("""
        <html>
          <body>Not a feed</body>
        </html>
        """))

        #expect(FeedParserService.detectFeedKind(in: document) == .unknown)
        #expect(document.detectedFeedKind == .unknown)
    }

    @Test
    func parseFeedThrowsUnsupportedFeedKindForUnknownDocuments() throws {
        let document = try FeedParserService.parse(makeData("""
        <opml version="2.0">
          <body />
        </opml>
        """))

        do {
            _ = try FeedParserService.parseFeed(document)
            Issue.record("Expected unknown feed kind to throw")
        } catch FeedParserError.unsupportedFeedKind(let kind) {
            #expect(kind == .unknown)
        } catch {
            Issue.record("Expected unsupported feed kind error, got \(error)")
        }
    }

    private func makeData(_ xml: String) -> Data {
        Data(xml.utf8)
    }
}
