import Foundation
import Testing
import SwiftUI
import UIKit
@testable import RSSReader

@Suite("Article Screen / Content Rendering / Text")
@MainActor
struct ArticleScreenTextRenderingTests {
    @Test(arguments: [
        "C(c) = 6c+1; (c), (C), (c)(c); © &copy; &#169; &#xA9;",
        "<p>С(c) = 6с+1; <a href='/formula'>C(c)</a>; © &copy; &#169; &#xA9;</p>",
        "&lt;p&gt;C(c) = 6c+1; (c), (C); © &amp;copy; &amp;#169; &amp;#xA9;&lt;/p&gt;",
        "<p>С© = 6с+1; upstream © must stay ©.</p>"
    ])
    func preservesCopyrightFromRSSPayloadThroughPersistenceAndReader(_ raw: String) throws {
        let xml = """
        <rss version="2.0">
          <channel>
            <title>Literal copyright fixture</title>
            <link>https://example.com</link>
            <item>
              <guid>copyright-fixture</guid>
              <title>Copyright fixture</title>
              <link>https://example.com/article</link>
              <description><![CDATA[\(raw)]]></description>
            </item>
          </channel>
        </rss>
        """
        let parsed = try FeedParserService.parseFeed(FeedParserService.parse(Data(xml.utf8)))
        let extracted = try #require(parsed.entries.first)
        #expect(extracted.contentText == raw)
        let normalized = FeedParserService.parsePipeline(parsed, feedURL: "https://example.com/feed.xml")
        let entry = try #require(normalized.entries.first)
        #expect(entry.contentText == raw)
        let fetchedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let payloads = try ArticleUpsertPayload.makeAllPrepared(entries: normalized.entries, fetchedAt: fetchedAt)
        #expect(payloads.first?.contentText == raw)
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try harness.feedRepository.insert(Feed(url: "https://example.com/feed.xml", title: "Fixture"))
        _ = try harness.articleRepository.reconcileFeedSnapshot(payloads, into: feed, fetchedAt: fetchedAt)
        try harness.saveModelContext()
        let stored = try #require(harness.articleRepository.fetchArticles(feedID: feed.id).first)
        #expect(stored.contentText == raw)
        let storedSearchText = stored.searchableText
        let dto = ReaderArticleDTO(article: stored, state: nil)
        #expect(dto.contentText == raw)
        let content = ArticleScreenContentState(article: dto)
        let expected = raw.hasPrefix("C(c)")
            ? "C(c) = 6c+1; (c), (C), (c)(c); © © © ©"
            : raw.hasPrefix("&lt;")
                ? "C(c) = 6c+1; (c), (C); © © © ©"
                : raw.contains("upstream")
                    ? "С© = 6с+1; upstream © must stay ©."
                    : "С(c) = 6с+1; C(c); © © © ©"
        #expect(content.body.blocks.count == 1)
        let block = try #require(content.body.blocks.first)
        guard case .paragraph(let text) = block else {
            Issue.record("Expected a paragraph from RSS")
            return
        }
        #expect(text.plainText == expected)
        #expect(String(text.attributedString.characters) == expected)
        if raw.contains("href=") {
            #expect(text.spans.contains { $0.text == "C(c)" && $0.linkURL?.absoluteString == "https://example.com/formula" })
        }
        #expect(stored.contentText == raw)
        #expect(stored.searchableText == storedSearchText)
    }

    @Test(arguments: [false, true])
    func preservesCopyrightTextAndLinkMetadataAcrossHTMLAndEscapedHTML(_ escaped: Bool) throws {
        let html = """
        <p>C(c) = 6c+1; (c), (C), (c)(c); ( c ), [c], (r), (tm), (a+b).</p>
        <p><a href="/formula?q=c&amp;n=1"><strong>C(c)</strong></a> <em>(c)</em> (<em>c</em>) <code>(C)</code>; © &copy; &#169; &#xA9;.</p>
        <pre>C(c) = 6c+1; (c), (C), © &copy; &#169; &#xA9;</pre>
        """
        let raw = escaped
            ? html.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            : html
        let article = makeReaderArticleDTO(
            summary: nil,
            contentHTML: escaped ? nil : raw,
            contentText: escaped ? raw : nil,
            canonicalURL: "https://example.com/article"
        )
        let content = ArticleScreenContentState(article: article)
        #expect(content.body.blocks.count == 3)
        guard case .paragraph(let first) = content.body.blocks.first,
              case .paragraph(let second) = content.body.blocks.dropFirst().first,
              case .codeBlock(let code) = content.body.blocks.last else {
            Issue.record("Expected two paragraphs and a code block")
            return
        }
        #expect(first.plainText == "C(c) = 6c+1; (c), (C), (c)(c); ( c ), [c], (r), (tm), (a+b).")
        #expect(second.plainText == "C(c) (c) (c) (C); © © © ©.")
        #expect(code == "C(c) = 6c+1; (c), (C), © © © ©")
        #expect(String(first.attributedString.characters) == first.plainText)
        #expect(String(second.attributedString.characters) == second.plainText)
        let linked = try #require(second.attributedString.runs.first { $0.link != nil })
        #expect(linked.link?.absoluteString == "https://example.com/formula?q=c&n=1")
        #expect(String(second.attributedString[linked.range].characters) == "C(c)")
        #expect(second.spans.contains { $0.text == "C(c)" && $0.isStrong && $0.linkURL != nil })
        #expect(second.spans.contains { $0.text == "(c)" && $0.isEmphasized })
        #expect(second.spans.contains { $0.text == "(C)" && $0.isCode })
    }

    @Test
    func preservesLiteralCopyrightSequencesInPlainTextParagraphs() {
        let raw = """
        C(c) = 6c+1; (c), (C), (c)(c).

        ( c ) [c] (r) (tm); © &copy; &#169; &#xA9;.
        """
        let content = ArticleScreenContentState(
            article: makeReaderArticleDTO(summary: nil, contentText: raw)
        )
        let expected = ["C(c) = 6c+1; (c), (C), (c)(c).", "( c ) [c] (r) (tm); © © © ©."]
        #expect(content.body.blocks == expected.map { .paragraph(.plainText($0)) })
        for block in content.body.blocks {
            if case .paragraph(let text) = block {
                #expect(String(text.attributedString.characters) == text.plainText)
            }
        }
    }

    @Test
    func articleScreenContentRendererRecoversMalformedAbbreviationMarkup() {
        let content = ArticleScreenContentState(
            article: makeReaderArticleDTO(
                contentText: """
                Практические приёмы снижения копипасты и упрощения конфигурирования множества сходных проектов в <abbr class="habraabbri title="тим сити" data-title=" тим сити
                " data-abbr="TeamCity">TeamCity.
                """
            )
        )

        #expect(
            content.body.blocks == [
                .paragraph(
                    .plainText(
                        "Практические приёмы снижения копипасты и упрощения конфигурирования множества сходных проектов в TeamCity."
                    )
                )
            ]
        )
        #expect(content.body.source == .contentText)
    }

    @Test
    func articleScreenContentRendererRendersValidAndEscapedInlineMarkupWithoutDamagingComparisons() {
        let validContent = ArticleScreenContentState(
            article: makeReaderArticleDTO(
                contentText: #"<p>Use <abbr title="Continuous Integration">CI</abbr>, <span>keep spans</span>, <strong>bold</strong>, <em>emphasis</em>, and <code>2 < 3</code>. Outside 5 > 4.</p>"#
            )
        )
        let escapedContent = ArticleScreenContentState(
            article: makeReaderArticleDTO(
                contentText: #"Use &amp;lt;abbr title=&amp;quot;Continuous Integration&amp;quot;&amp;gt;CI&amp;lt;/abbr&amp;gt; once."#
            )
        )

        #expect(
            validContent.body.blocks == [
                .paragraph(
                    ArticleScreenTextBlock(
                        spans: [
                            ArticleScreenTextSpan(text: "Use CI, keep spans, "),
                            ArticleScreenTextSpan(text: "bold", isStrong: true),
                            ArticleScreenTextSpan(text: ", "),
                            ArticleScreenTextSpan(text: "emphasis", isEmphasized: true),
                            ArticleScreenTextSpan(text: ", and "),
                            ArticleScreenTextSpan(text: "2 < 3", isCode: true),
                            ArticleScreenTextSpan(text: ". Outside 5 > 4.")
                        ]
                    )
                )
            ]
        )
        #expect(escapedContent.body.blocks == [.paragraph(.plainText("Use CI once."))])
    }

    @Test
    func articleScreenContentRendererRendersEscapedHTMLTextAsReadableParagraphsAndLinks() {
        let content = ArticleScreenContentState(
            article: makeReaderArticleDTO(
                contentText: """
                &lt;p&gt;Это уже другой уровень&lt;/p&gt;
                &lt;p&gt;Сообщение &lt;a href=&quot;https://thecode.media/komanda-flipper-zero&quot;&gt;Создатели Flipper Zero анонсировали карманный Linux-компьютер&lt;/a&gt; появились сначала на &lt;a href=&quot;https://thecode.media&quot;&gt;Журнал «Код»&lt;/a&gt;&lt;/p&gt;
                """
            )
        )

        #expect(
            content.body.blocks == [
                .paragraph(.plainText("Это уже другой уровень")),
                .paragraph(
                    ArticleScreenTextBlock(
                        spans: [
                            ArticleScreenTextSpan(text: "Сообщение "),
                            ArticleScreenTextSpan(
                                text: "Создатели Flipper Zero анонсировали карманный Linux-компьютер",
                                linkURL: URL(string: "https://thecode.media/komanda-flipper-zero")!
                            ),
                            ArticleScreenTextSpan(text: " появились сначала на "),
                            ArticleScreenTextSpan(
                                text: "Журнал «Код»",
                                linkURL: URL(string: "https://thecode.media")!
                            )
                        ]
                    )
                )
            ]
        )
        #expect(content.body.source == .contentText)
    }

    @Test
    func articleScreenContentRendererRendersEscapedHTMLSummaryBeforeFallbackNotice() {
        let content = ArticleScreenContentState(
            article: makeReaderArticleDTO(
                summary: "&lt;p&gt;Short &lt;strong&gt;summary&lt;/strong&gt; paragraph.&lt;/p&gt;",
                contentHTML: nil,
                contentText: nil
            )
        )

        #expect(
            content.body.blocks == [
                .paragraph(
                    ArticleScreenTextBlock(
                        spans: [
                            ArticleScreenTextSpan(text: "Short "),
                            ArticleScreenTextSpan(text: "summary", isStrong: true),
                            ArticleScreenTextSpan(text: " paragraph.")
                        ]
                    )
                ),
                .fallbackNotice(ReadingLocalization.summaryOnlyFallbackNotice)
            ]
        )
        #expect(content.body.source == .summary)
    }

    @Test
    func articleScreenContentRendererPreservesAnchorMetadataInsideHTMLParagraphs() {
        let content = ArticleScreenContentState(
            article: makeReaderArticleDTO(
                contentHTML: """
                <p>Read <a href="/guides/swift">Swift Guide</a> today.</p>
                """,
                canonicalURL: "https://example.com/articles/body"
            )
        )

        #expect(
            content.body.blocks == [
                .paragraph(
                    ArticleScreenTextBlock(
                        spans: [
                            ArticleScreenTextSpan(text: "Read "),
                            ArticleScreenTextSpan(
                                text: "Swift Guide",
                                linkURL: URL(string: "https://example.com/guides/swift")!
                            ),
                            ArticleScreenTextSpan(text: " today.")
                        ]
                    )
                )
            ]
        )
        #expect(content.body.source == .contentHTML)
    }

    @Test
    func articleScreenContentRendererDetectsLinksInsidePlainTextBody() {
        let content = ArticleScreenContentState(
            article: makeReaderArticleDTO(
                contentText: "Read more at https://example.com/guides/swift today."
            )
        )

        #expect(
            content.body.blocks == [
                .paragraph(
                    ArticleScreenTextBlock(
                        spans: [
                            ArticleScreenTextSpan(text: "Read more at "),
                            ArticleScreenTextSpan(
                                text: "https://example.com/guides/swift",
                                linkURL: URL(string: "https://example.com/guides/swift")!
                            ),
                            ArticleScreenTextSpan(text: " today.")
                        ]
                    )
                )
            ]
        )
        #expect(content.body.source == .contentText)
    }

    @Test
    func articleScreenTextBlockBuildsAttributedStringWithLinkAttributes() {
        let textBlock = ArticleScreenTextBlock(
            spans: [
                ArticleScreenTextSpan(text: "Read "),
                ArticleScreenTextSpan(
                    text: "Swift Guide",
                    linkURL: URL(string: "https://example.com/guides/swift")!
                ),
                ArticleScreenTextSpan(text: " today.")
            ]
        )

        let attributedString = textBlock.attributedString

        #expect(String(attributedString.characters) == "Read Swift Guide today.")

        let linkRuns = attributedString.runs.filter { $0.link != nil }
        #expect(linkRuns.count == 1)
        #expect(linkRuns.first?.link == URL(string: "https://example.com/guides/swift")!)
        #expect(String(attributedString[linkRuns[0].range].characters) == "Swift Guide")
    }

    @Test(arguments: ["Before <mark>A&amp;B</mark> after", "Before <mark>A&amp;B after"])
    func markUsesThemeTextWithoutBackground(_ html: String) throws {
        let content = ArticleScreenContentState(
            article: makeReaderArticleDTO(contentHTML: "<p>\(html)</p><p>Next paragraph.</p>")
        )
        #expect(content.body.blocks.count == 2)
        guard case .paragraph(let text) = content.body.blocks.first,
              case .paragraph(let next) = content.body.blocks.last else {
            Issue.record("Expected two readable paragraphs")
            return
        }
        #expect(text.plainText == "Before A&B after")
        #expect(String(text.attributedString.characters) == text.plainText)
        #expect(next.plainText == "Next paragraph.")
        #expect(text.attributedString.runs.allSatisfy {
            $0.swiftUI.backgroundColor == nil && $0.swiftUI.foregroundColor == nil
        })
    }

    @Test
    func markPreservesNestedStylesAndLinksWithoutBackground() throws {
        let content = ArticleScreenContentState(
            article: makeReaderArticleDTO(
                contentHTML: """
                <p><a href="/before">before</a> <mark><strong><em>bold italic</em></strong> <code>code</code> <a href="/inside"><strong>link</strong></a> <ins>new</ins> <del>old</del> x<sup>2</sup> H<sub>2</sub>O <kbd>key</kbd> <samp>output</samp> <var>value</var> <cite>Book</cite></mark> <a href="/around"><mark>around</mark></a> <a href="/after">after</a></p>
                """,
                canonicalURL: "https://example.com/article"
            )
        )
        guard case .paragraph(let text) = content.body.blocks.first else {
            Issue.record("Expected a nested-semantics paragraph")
            return
        }
        let attributed = text.attributedString
        #expect(String(attributed.characters) == "before bold italic code link new old x2 H2O key output value Book around after")
        #expect(attributed.runs.allSatisfy { $0.swiftUI.backgroundColor == nil && $0.swiftUI.foregroundColor == nil })
        let combined = try #require(attributed.runs.first {
            String(attributed[$0.range].characters) == "bold italic"
        })
        #expect(combined.inlinePresentationIntent?.contains(.stronglyEmphasized) == true)
        #expect(combined.inlinePresentationIntent?.contains(.emphasized) == true)
        let code = try #require(attributed.runs.first { String(attributed[$0.range].characters) == "code" })
        #expect(code.inlinePresentationIntent?.contains(.code) == true)
        #expect(attributed.runs.contains { $0.swiftUI.underlineStyle == .single })
        #expect(attributed.runs.contains { $0.inlinePresentationIntent?.contains(.strikethrough) == true })
        #expect(attributed.runs.contains { $0.swiftUI.baselineOffset == 4 })
        #expect(attributed.runs.contains { $0.swiftUI.baselineOffset == -2 })
        for name in ["before", "inside", "around", "after"] {
            #expect(attributed.runs.contains { $0.link == URL(string: "https://example.com/\(name)") })
        }

        // Mark contributes no attributes; every other supported intent stays identical.
        for span in text.spans where span.isMarked {
            let unmarked = ArticleScreenTextSpan(
                text: span.text, linkURL: span.linkURL,
                isStrong: span.isStrong, isEmphasized: span.isEmphasized, isCode: span.isCode,
                verticalAlignment: span.verticalAlignment, isDeleted: span.isDeleted,
                isInserted: span.isInserted, codeSemantic: span.codeSemantic, isCitation: span.isCitation
            )
            #expect(ArticleScreenTextBlock(spans: [span]).attributedString ==
                    ArticleScreenTextBlock(spans: [unmarked]).attributedString)
        }
    }

    @Test
    func articleScreenContentRendererPreservesExtendedInlineSemantics() {
        let content = ArticleScreenContentState(
            article: makeReaderArticleDTO(
                contentHTML: "<p><mark>marked</mark> H<sub>2</sub>O x<sup>2</sup> <del>old</del> <ins>new</ins> <kbd>⌘K</kbd> <samp>output</samp> <var>value</var> <cite>Book</cite></p>"
            )
        )

        guard case .paragraph(let text) = content.body.blocks.first else {
            Issue.record("Expected an extended-semantics paragraph")
            return
        }

        #expect(text.plainText == "marked H2O x2 old new ⌘K output value Book")
        #expect(text.spans.contains { $0.text == "marked" && $0.isMarked })
        #expect(text.spans.contains { $0.text == "2" && $0.verticalAlignment == .lowered })
        #expect(text.spans.contains { $0.text == "2" && $0.verticalAlignment == .superscript })
        #expect(text.spans.contains { $0.text == "old" && $0.isDeleted })
        #expect(text.spans.contains { $0.text == "new" && $0.isInserted })
        #expect(text.spans.contains { $0.text == "⌘K" && $0.codeSemantic == .keyboardInput && $0.isCode })
        #expect(text.spans.contains { $0.text == "output" && $0.codeSemantic == .sampleOutput && $0.isCode })
        #expect(text.spans.contains { $0.text == "value" && $0.codeSemantic == .variable })
        #expect(text.spans.contains { $0.text == "Book" && $0.isCitation })
    }

    @Test
    func articleScreenContentRendererCombinesExtendedSemanticsWithLinksAndExistingStyles() {
        let content = ArticleScreenContentState(
            article: makeReaderArticleDTO(
                contentHTML: "<p><a href=\"/changes\"><strong><mark>important</mark></strong> <del>old</del></a> <cite><em>引用</em></cite> &amp; <code><var>値</var></code></p>",
                articleURL: "https://example.com/articles/1"
            )
        )

        guard case .paragraph(let text) = content.body.blocks.first else {
            Issue.record("Expected a nested-semantics paragraph")
            return
        }

        let linkURL = URL(string: "https://example.com/changes")!
        #expect(text.plainText == "important old 引用 & 値")
        #expect(text.spans.contains { $0.text == "important" && $0.isStrong && $0.isMarked && $0.linkURL == linkURL })
        #expect(text.spans.contains { $0.text == "old" && $0.isDeleted && $0.linkURL == linkURL })
        #expect(text.spans.contains { $0.text == "引用" && $0.isCitation && $0.isEmphasized })
        #expect(text.spans.contains { $0.text == "値" && $0.codeSemantic == .variable && $0.isCode })
        #expect(String(text.attributedString.characters) == text.plainText)
    }

    @Test
    func articleScreenContentRendererKeepsMalformedAndAngleBracketTextReadable() {
        let malformed = ArticleScreenContentState(
            article: makeReaderArticleDTO(contentHTML: "<p>Before <mark>highlight <strong>bold</strong> after</p>")
        )
        let comparison = ArticleScreenContentState(
            article: makeReaderArticleDTO(contentHTML: "<p>Use 2 < 3, 5 > 4, &lt;tag&gt; and <mark>A&amp;B</mark>.</p>")
        )

        guard case .paragraph(let malformedText) = malformed.body.blocks.first,
              case .paragraph(let comparisonText) = comparison.body.blocks.first else {
            Issue.record("Expected readable fallback paragraphs")
            return
        }

        #expect(malformedText.plainText == "Before highlight bold after")
        #expect(comparisonText.plainText == "Use 2 < 3, 5 > 4, <tag> and A&B.")
    }

    @Test
    func articleScreenContentRendererUsesSummaryWithFallbackNoticeWhenFullBodyIsUnavailable() {
        let content = ArticleScreenContentState(
            article: makeReaderArticleDTO(
                summary: """
                Short summary paragraph.

                Another summary paragraph.
                """,
                contentHTML: nil,
                contentText: nil
            )
        )

        #expect(
            content.body.blocks == [
                .paragraph(.plainText("Short summary paragraph.")),
                .paragraph(.plainText("Another summary paragraph.")),
                .fallbackNotice(ReadingLocalization.summaryOnlyFallbackNotice)
            ]
        )
        #expect(content.body.source == .summary)
    }

    @Test
    func articleScreenContentRendererBuildsGracefulFallbackWhenFeedHasNoBodyContent() {
        let content = ArticleScreenContentState(
            article: makeReaderArticleDTO(
                summary: nil,
                contentHTML: nil,
                contentText: nil
            )
        )

        #expect(
            content.body.blocks == [
                .fallbackNotice(ReadingLocalization.emptyBodyFallbackNotice)
            ]
        )
        #expect(content.body.source == .empty)
    }
}
