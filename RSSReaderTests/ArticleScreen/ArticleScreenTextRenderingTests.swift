import Foundation
import Testing
import UIKit
@testable import RSSReader

@Suite("Article Screen / Content Rendering / Text")
@MainActor
struct ArticleScreenTextRenderingTests {
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
                .fallbackNotice("This article included only a summary in the received feed.")
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
                .fallbackNotice("This article included only a summary in the received feed.")
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
                .fallbackNotice("This article did not include body content in the received feed.")
            ]
        )
        #expect(content.body.source == .empty)
    }
}
