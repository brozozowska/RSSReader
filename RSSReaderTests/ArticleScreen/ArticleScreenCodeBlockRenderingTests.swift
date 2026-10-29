import Foundation
import Testing
import UIKit
@testable import RSSReader

@Suite("Article Screen / Code Block Rendering")
@MainActor
struct ArticleScreenCodeBlockRenderingTests {
    @Test(arguments: [0, 1, 2])
    func preservesSourceWhitespaceAndLiteralMarkupThroughFeedAndReader(_ escapingLevels: Int) throws {
        let source = "\n    if value < 3 {\n\tprint(\"<p><!-- literal --></p>\")\n\n    }  \n"
        var html = "<pre><code class='language-swift'>" + source
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;") + "</code></pre>"
        for _ in 0..<escapingLevels {
            html = html.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
        }
        let xml = """
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>Code fixture</title><id>urn:code-feed</id><updated>2026-10-11T00:00:00Z</updated>
          <entry><title>Code</title><id>urn:code</id><updated>2026-10-11T00:00:00Z</updated>
            <content type="html"><![CDATA[\(html)]]></content>
          </entry>
        </feed>
        """
        let parsed = try FeedParserService.parseFeed(FeedParserService.parse(Data(xml.utf8)))
        let normalized = FeedParserService.parsePipeline(parsed, feedURL: "https://example.com/feed.xml")
        let entry = try #require(normalized.entries.first)
        let fetchedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let payloads = try ArticleUpsertPayload.makeAllPrepared(entries: normalized.entries, fetchedAt: fetchedAt)
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try harness.feedRepository.insert(Feed(url: "https://example.com/feed.xml", title: "Code fixture"))
        _ = try harness.articleRepository.reconcileFeedSnapshot(payloads, into: feed, fetchedAt: fetchedAt)
        try harness.saveModelContext()
        let article = try #require(harness.articleRepository.fetchArticles(feedID: feed.id).first)
        let searchableText = article.searchableText
        let content = ArticleScreenContentState(article: ReaderArticleDTO(article: article, state: nil))

        #expect(content.body.blocks == [.codeBlock(source)])
        #expect(article.contentHTML == entry.contentHTML)
        #expect(article.contentText == entry.contentText)
        #expect(article.searchableText == searchableText)
    }

    @Test
    func distinguishesBarePreFromExplicitCodeAndRetainsInlineSemantics() {
        let content = ArticleScreenContentState(article: makeReaderArticleDTO(
            contentHTML: "<pre>    Wrapped prose\n    第二行</pre><pre><code>    let value = 42</code></pre><p>Use <code>AccountViewModel</code>.</p>"
        ))
        #expect(content.body.blocks == [
            .preformattedText("    Wrapped prose\n    第二行"),
            .codeBlock("    let value = 42"),
            .paragraph(ArticleContentTextBlock(spans: [
                ArticleContentTextSpan(text: "Use "),
                ArticleContentTextSpan(text: "AccountViewModel", isCode: true),
                ArticleContentTextSpan(text: ".")
            ]))
        ])
    }

    @Test(arguments: ["Example: ", "<!-- literal -->"])
    func barePreLiteralCodeTagsDoNotBecomeAnEnclosingCodeWrapper(_ prefix: String) {
        let source = prefix + "<code>literal</code>"
        let blocks = ArticleContentBodyPayloadRenderer.renderHTML(
            "<pre>\(source)</pre>", article: makeReaderArticleDTO()
        )
        #expect(blocks == [.preformattedText(source)])
    }

    @Test
    func suppressesWhitespaceOnlyPreAndCode() {
        let article = makeReaderArticleDTO(summary: nil, contentHTML: nil)
        let blocks = ArticleContentBodyPayloadRenderer.renderHTML(
            "<pre> \n\t </pre><pre><code> \n\t </code></pre>",
            article: article
        )
        #expect(blocks.isEmpty)
    }

    @Test(arguments: [CGFloat(17), CGFloat(36)])
    func wrapsCollapsedCodeWithoutChangingCopyableSource(_ fontSize: CGFloat) throws {
        let source = "import SwiftUI import ScreenView struct AccountView: ScreenView { let viewModel: AccountViewModel // Finite, cancellation-aware setup. }"
        let content = ArticleScreenContentState(article: makeReaderArticleDTO(
            contentHTML: "<pre><code>\(source)</code></pre>"
        ))
        #expect(content.body.blocks == [.codeBlock(source)])

        let view = ReaderArticleWrappingCodeTextView()
        view.setCode(source, fontSize: fontSize)
        view.setCode(source, fontSize: fontSize)
        #expect(view.text == source)
        #expect(view.attributedText.string == source)
        #expect(view.isSelectable && !view.isEditable && !view.isScrollEnabled)
        let paragraph = try #require(view.attributedText.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        #expect(paragraph.hyphenationFactor == 0)
        #expect(paragraph.firstLineHeadIndent == 0)
        #expect(paragraph.headIndent > 0)
        #expect(paragraph.baseWritingDirection == .leftToRight)

        let narrow = view.sizeThatFits(CGSize(width: 280, height: CGFloat.greatestFiniteMagnitude))
        let wide = view.sizeThatFits(CGSize(width: 700, height: CGFloat.greatestFiniteMagnitude))
        #expect(narrow.height > wide.height)
        #expect(narrow.height.isFinite && narrow.height > fontSize)
        #expect(view.text == source)
    }
}
