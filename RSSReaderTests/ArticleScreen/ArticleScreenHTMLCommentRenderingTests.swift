import Foundation
import Testing
@testable import RSSReader

@Suite("Article Screen / HTML Comments")
@MainActor
struct ArticleScreenHTMLCommentRenderingTests {
    @Test(arguments: [0, 1, 2, 3])
    func ignoresRedditCommentsAcrossOuterEscaping(_ levels: Int) {
        let html = "<!-- SC_OFF --><div class=\"md\"><p>Visible body</p></div><!-- SC_ON -->"
        let content = ArticleScreenContentState(article: makeReaderArticleDTO(contentHTML: escaped(html, levels: levels)))
        #expect(content.body.blocks == [.paragraph(.plainText("Visible body"))])
    }

    @Test
    func excludesCommentedStructureBeforeExtractingBlocksAndLinks() {
        let html = """
        <!-- <pre>not literal code</pre><p>hidden</p><img src="https://example.com/hidden.png">
        <a href="/hidden">hidden link</a><details><summary>hidden control</summary>hidden panel</details> -->
        <h2>Visible</h2><!-- adjacent --><!-- second -->
        <p>A<!-- internal
        note -->B <strong>bold</strong> <a href="/visible">link</a></p>
        <ul><li>Item<!-- note --></li></ul>
        """
        let baseline = """
        <h2>Visible</h2>
        <p>AB <strong>bold</strong> <a href="/visible">link</a></p>
        <ul><li>Item</li></ul>
        """
        let content = ArticleScreenContentState(article: makeReaderArticleDTO(contentHTML: html))
        let expected = ArticleScreenContentState(article: makeReaderArticleDTO(contentHTML: baseline))
        #expect(content.body.blocks == expected.body.blocks)
        #expect(content.body.blocks.containsImageBlock == false)
    }

    @Test(arguments: [0, 1, 2])
    func preservesLiteralCommentExamplesAndQuotedAttributes(_ levels: Int) {
        let html = """
        <p>Example: &lt;!-- literal prose --&gt;.</p>
        <p><code>&lt;!-- literal inline --&gt;</code></p>
        <pre><code>&lt;!-- &lt;p&gt;literal block&lt;/p&gt; --&gt;</code></pre>
        <p><abbr title="<!-- attribute > still quoted -->">CI</abbr></p>
        """
        let content = ArticleScreenContentState(article: makeReaderArticleDTO(contentHTML: escaped(html, levels: levels)))
        #expect(content.body.blocks == [
            .paragraph(.plainText("Example: <!-- literal prose -->.")),
            .paragraph(ArticleScreenTextBlock(spans: [ArticleScreenTextSpan(text: "<!-- literal inline -->", isCode: true)])),
            .codeBlock("<!-- <p>literal block</p> -->"),
            .paragraph(.plainText("CI"))
        ])
    }

    @Test
    func preservesRawCodeComments() {
        let content = ArticleScreenContentState(article: makeReaderArticleDTO(
            contentHTML: "<pre><!-- literal block --></pre><p><code><!-- literal inline --></code></p>"
        ))
        #expect(content.body.blocks == [
            .codeBlock("<!-- literal block -->"),
            .paragraph(ArticleScreenTextBlock(spans: [ArticleScreenTextSpan(text: "<!-- literal inline -->", isCode: true)]))
        ])
    }

    @Test
    func unclosedCommentKeepsVisiblePrefixAndDiscardsRemainder() {
        let content = ArticleScreenContentState(article: makeReaderArticleDTO(
            contentHTML: "<p>Visible</p><!-- unclosed <p>hidden</p><img src=\"https://example.com/hidden.png\">"
        ))
        #expect(content.body.blocks == [.paragraph(.plainText("Visible"))])
    }

    @Test
    func commentOnlyHTMLDoesNotReturnThroughDuplicateFallbacks() {
        let html = "<!-- SC_OFF --><!-- SC_ON -->"
        let content = ArticleScreenContentState(article: makeReaderArticleDTO(
            summary: escaped(html, levels: 2), contentHTML: html, contentText: " \n" + html
        ))
        #expect(content.body.source == .empty)
        #expect(content.body.blocks == [.fallbackNotice(ReadingLocalization.emptyBodyFallbackNotice)])
    }

    @Test
    func commentOnlyHTMLUsesIndependentReadableFallback() {
        let content = ArticleScreenContentState(article: makeReaderArticleDTO(
            summary: "Summary", contentHTML: "<!-- metadata -->", contentText: "Readable text"
        ))
        #expect(content.body.source == .contentText)
        #expect(content.body.blocks == [.paragraph(.plainText("Readable text"))])
    }

    @Test
    func escapedCommentInHTMLProseWithoutTagsStaysLiteral() {
        let content = ArticleScreenContentState(article: makeReaderArticleDTO(
            contentHTML: "Example: &lt;!-- literal prose --&gt;."
        ))
        #expect(content.body.blocks == [.paragraph(.plainText("Example: <!-- literal prose -->."))])
    }

    @Test
    func largeCommentPayloadKeepsOnlyVisibleNeighbors() {
        let hidden = String(repeating: "<img src='https://example.com/hidden.png'><code>hidden</code>\n", count: 10_000)
        let content = ArticleScreenContentState(article: makeReaderArticleDTO(
            contentHTML: "<p>Before</p><!--" + hidden + "--><p>After</p>"
        ))
        #expect(content.body.blocks == [.paragraph(.plainText("Before")), .paragraph(.plainText("After"))])
    }

    @Test(arguments: ["Use <!-- literal example --> here.", "Use <!-- <p>literal markup</p> --> here."])
    func genuinePlainTextPreservesLiteralComments(_ text: String) {
        let content = ArticleScreenContentState(article: makeReaderArticleDTO(
            contentText: text
        ))
        #expect(content.body.source == .contentText)
        #expect(content.body.blocks == [.paragraph(.plainText(text))])
    }

    private func escaped(_ value: String, levels: Int) -> String {
        (0..<levels).reduce(value) { result, _ in
            result.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
        }
    }
}
