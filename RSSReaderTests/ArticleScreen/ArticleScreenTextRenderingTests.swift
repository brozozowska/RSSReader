import Foundation
import Testing
import UIKit
@testable import RSSReader

@Suite("Article Screen / Content Rendering / Text")
@MainActor
struct ArticleScreenTextRenderingTests {
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
