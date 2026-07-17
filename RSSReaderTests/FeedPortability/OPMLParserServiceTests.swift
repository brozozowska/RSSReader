import Foundation
import Testing
@testable import RSSReader

@Suite("Feed Portability / OPML Parser Service")
@MainActor
struct OPMLParserServiceTests {
    @Test
    func parsesOPMLTwoDocumentWithNestedFoldersAndFeedAttributes() throws {
        let document = try OPMLParserService.parse(
            makeData(
                """
                <?xml version="1.0" encoding="UTF-8"?>
                <opml version="2.0">
                  <head>
                    <title>My Feeds</title>
                  </head>
                  <body>
                    <outline text="Technology">
                      <outline title="Apple">
                        <outline
                          text="Swift Blog"
                          title="Swift Blog Title"
                          type="rss"
                          xmlUrl=" https://swift.org/blog/feed.xml "
                          htmlUrl=" https://swift.org/blog " />
                      </outline>
                    </outline>
                    <outline
                      text="Ungrouped Feed"
                      xmlUrl="https://example.com/feed.xml"
                      htmlUrl="https://example.com" />
                  </body>
                </opml>
                """
            )
        )

        #expect(document.version == "2.0")
        #expect(document.title == "My Feeds")
        #expect(document.ignoredOutlineCount == 0)
        #expect(document.feeds.count == 2)
        #expect(document.feeds[0] == OPMLFeedOutlineDTO(
            folderPath: ["Technology", "Apple"],
            title: "Swift Blog Title",
            text: "Swift Blog",
            xmlURL: "https://swift.org/blog/feed.xml",
            htmlURL: "https://swift.org/blog"
        ))
        #expect(document.feeds[1].folderPath.isEmpty)
        #expect(document.feeds[1].displayTitle == "Ungrouped Feed")
    }

    @Test
    func parsesOPMLOneDocumentAndUsesTextAsDisplayTitleFallback() throws {
        let document = try OPMLParserService.parse(
            makeData(
                """
                <opml version="1.0">
                  <body>
                    <outline text="News">
                      <outline text="Example News" xmlUrl="https://example.com/rss" />
                    </outline>
                  </body>
                </opml>
                """
            )
        )

        let feed = try #require(document.feeds.first)
        #expect(document.version == "1.0")
        #expect(feed.folderPath == ["News"])
        #expect(feed.title == nil)
        #expect(feed.text == "Example News")
        #expect(feed.displayTitle == "Example News")
    }

    @Test
    func ignoresLeafOutlinesWithoutFeedURLAndKeepsValidSiblings() throws {
        let document = try OPMLParserService.parse(
            makeData(
                """
                <opml version="2.0">
                  <body>
                    <outline text="Folder">
                      <outline text="Missing URL" />
                      <outline text="Valid" xmlUrl="https://example.com/valid.xml" />
                    </outline>
                    <outline text="Unknown Leaf" />
                  </body>
                </opml>
                """
            )
        )

        #expect(document.ignoredOutlineCount == 2)
        #expect(document.feeds.map(\.text) == ["Valid"])
        #expect(document.feeds.map(\.folderPath) == [["Folder"]])
    }

    @Test
    func emptyDocumentThrowsEmptyDocumentError() {
        assertEmptyDocumentError(for: Data())
        assertEmptyDocumentError(for: makeData(" \n\t "))
    }

    @Test
    func malformedXMLReportsLineColumnAndParserMessage() {
        do {
            _ = try OPMLParserService.parse(
                makeData(
                    """
                    <opml>
                      <body>
                    </opml>
                    """
                )
            )
            Issue.record("Expected malformed XML to throw")
        } catch OPMLParserError.malformedXML(let line, let column, let message) {
            #expect(line > 0)
            #expect(column > 0)
            #expect(message.isEmpty == false)
        } catch {
            Issue.record("Expected malformed XML error, got \(error)")
        }
    }

    @Test
    func unsupportedRootAndMissingBodyThrowParserErrors() {
        do {
            _ = try OPMLParserService.parse(makeData("<rss><channel /></rss>"))
            Issue.record("Expected unsupported root to throw")
        } catch OPMLParserError.unsupportedRootElement(let rootName) {
            #expect(rootName == "rss")
        } catch {
            Issue.record("Expected unsupported root error, got \(error)")
        }

        do {
            _ = try OPMLParserService.parse(makeData("<opml version=\"2.0\"><head /></opml>"))
            Issue.record("Expected missing body to throw")
        } catch OPMLParserError.missingBody {
            return
        } catch {
            Issue.record("Expected missing body error, got \(error)")
        }
    }

    @Test
    func defaultOPMLPolicyUsesAppLevelStructuralBudget() {
        #expect(
            XMLParserStructuralPolicy.opml.budget
                == AppComposition.resourceBudgetContract.opml
        )
    }

    @Test
    func rejectsElementThatExceedsOPMLDepthLimit() {
        let policy = makeOPMLPolicy(maximumDepth: 4)

        assertResourceLimit(
            for: "<opml><body><outline><outline><outline /></outline></outline></body></opml>",
            policy: policy,
            expected: .xmlDepthExceeded(
                input: .opml,
                maximumDepth: 4,
                actualDepth: 5
            )
        )
    }

    @Test
    func rejectsElementThatExceedsOPMLElementCountLimit() {
        let policy = makeOPMLPolicy(maximumElementCount: 4)

        assertResourceLimit(
            for: "<opml><body><outline /><outline /><outline /></body></opml>",
            policy: policy,
            expected: .xmlElementCountExceeded(
                input: .opml,
                maximumCount: 4,
                actualCount: 5
            )
        )
    }

    @Test
    func allowsFeedOutlinesAtEntryLimitAndRejectsNextFeedOutline() throws {
        let policy = makeOPMLPolicy(maximumEntryCount: 2)
        let acceptedDocument = try OPMLParserService.parse(
            makeData(
                "<opml><body><outline xmlUrl=\"https://example.com/1\" /><outline xmlUrl=\"https://example.com/2\" /></body></opml>"
            ),
            structuralPolicy: policy
        )

        #expect(acceptedDocument.feeds.count == 2)

        assertResourceLimit(
            for: "<opml><body><outline text=\"Folder\"><outline xmlUrl=\"https://example.com/1\" /><outline xmlUrl=\"https://example.com/2\" /><outline xmlUrl=\"https://example.com/3\" /></outline></body></opml>",
            policy: policy,
            expected: .xmlEntryCountExceeded(
                input: .opml,
                maximumCount: 2,
                actualCount: 3
            )
        )
    }

    @Test
    func countsOnlyOPMLOutlinesThatCollectorCanMaterialize() throws {
        let policy = makeOPMLPolicy(maximumEntryCount: 1)
        let document = try OPMLParserService.parse(
            makeData(
                "<opml><head><outline xmlUrl=\"https://example.com/head\" /></head><body><outline xmlUrl=\"https://example.com/outer\"><outline xmlUrl=\"https://example.com/unreachable\" /></outline></body></opml>"
            ),
            structuralPolicy: policy
        )

        #expect(document.feeds.map(\.xmlURL) == ["https://example.com/outer"])
    }

    private func makeData(_ xml: String) -> Data {
        Data(xml.utf8)
    }

    private func makeOPMLPolicy(
        maximumElementCount: Int = 100,
        maximumDepth: Int = 10,
        maximumEntryCount: Int = 10
    ) -> XMLParserStructuralPolicy {
        XMLParserStructuralPolicy(
            budget: RuntimeXMLInputBudget(
                body: AppComposition.resourceBudgetContract.opml.body,
                maximumElementCount: maximumElementCount,
                maximumDepth: maximumDepth,
                maximumEntryCount: maximumEntryCount
            ),
            materializedEntryKind: .opml
        )
    }

    private func assertResourceLimit(
        for xml: String,
        policy: XMLParserStructuralPolicy,
        expected: AppResourceBudgetViolation
    ) {
        do {
            _ = try OPMLParserService.parse(
                makeData(xml),
                structuralPolicy: policy
            )
            Issue.record("Expected OPML resource limit failure")
        } catch OPMLParserError.resourceLimitExceeded(let violation) {
            #expect(violation == expected)
        } catch {
            Issue.record("Expected OPML resource limit failure, got \(error)")
        }
    }

    private func assertEmptyDocumentError(for data: Data) {
        do {
            _ = try OPMLParserService.parse(data)
            Issue.record("Expected empty document to throw")
        } catch OPMLParserError.emptyDocument {
            return
        } catch {
            Issue.record("Expected empty document error, got \(error)")
        }
    }
}
