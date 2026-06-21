import Foundation
import Testing
import UIKit
@testable import RSSReader

@Suite("Article Screen / Content Rendering / HTML Blocks")
@MainActor
struct ArticleScreenHTMLBlockRenderingTests {
    @Test
    func articleScreenContentRendererParsesHTMLParagraphsAndInlineImagesInOrder() {
        let content = ArticleScreenContentState(
            article: makeReaderArticleDTO(
                summary: "Short summary",
                contentHTML: """
                <p>First paragraph.</p>
                <img src="https://example.com/images/inline.png">
                <p>Second <strong>paragraph</strong>.</p>
                """,
                contentText: "Plain text fallback"
            )
        )

        #expect(
            content.body.blocks == [
                .paragraph(.plainText("First paragraph.")),
                .image(URL(string: "https://example.com/images/inline.png")!),
                .paragraph(
                    ArticleScreenTextBlock(
                        spans: [
                            ArticleScreenTextSpan(text: "Second "),
                            ArticleScreenTextSpan(text: "paragraph", isStrong: true),
                            ArticleScreenTextSpan(text: ".")
                        ]
                    )
                )
            ]
        )
        #expect(content.body.source == .contentHTML)
    }

    @Test
    func articleScreenContentRendererPreservesHTMLHeadingsListsAndInlineFormatting() {
        let content = ArticleScreenContentState(
            article: makeReaderArticleDTO(
                contentHTML: """
                <h2>Что такое аванс</h2>
                <p>Аванс — это часть <strong>зарплаты</strong>, которую выплачивают заранее.</p>
                <ul>
                    <li>Оклад</li>
                    <li><em>Компенсационные</em> надбавки</li>
                </ul>
                <ol>
                    <li>Первый шаг</li>
                    <li>Второй <code>step</code></li>
                </ol>
                """
            )
        )

        #expect(
            content.body.blocks == [
                .heading(level: 2, .plainText("Что такое аванс")),
                .paragraph(
                    ArticleScreenTextBlock(
                        spans: [
                            ArticleScreenTextSpan(text: "Аванс — это часть "),
                            ArticleScreenTextSpan(text: "зарплаты", isStrong: true),
                            ArticleScreenTextSpan(text: ", которую выплачивают заранее.")
                        ]
                    )
                ),
                .list(
                    ArticleScreenListBlock(
                        kind: .unordered,
                        items: [
                            .plainText("Оклад"),
                            ArticleScreenTextBlock(
                                spans: [
                                    ArticleScreenTextSpan(text: "Компенсационные", isEmphasized: true),
                                    ArticleScreenTextSpan(text: " надбавки")
                                ]
                            )
                        ]
                    )
                ),
                .list(
                    ArticleScreenListBlock(
                        kind: .ordered,
                        items: [
                            .plainText("Первый шаг"),
                            ArticleScreenTextBlock(
                                spans: [
                                    ArticleScreenTextSpan(text: "Второй "),
                                    ArticleScreenTextSpan(text: "step", isCode: true)
                                ]
                            )
                        ]
                    )
                )
            ]
        )
    }

    @Test
    func articleScreenContentRendererPreservesBlockquotesPreformattedTextAndDividers() {
        let content = ArticleScreenContentState(
            article: makeReaderArticleDTO(
                contentHTML: """
                <blockquote>
                    <p>Первая цитата.</p>
                    <p>Вторая <a href="/quote">цитата</a>.</p>
                </blockquote>
                <pre><code>let value = 42
                print(value)</code></pre>
                <hr>
                """
            )
        )

        #expect(
            content.body.blocks == [
                .blockquote(
                    [
                        .plainText("Первая цитата."),
                        ArticleScreenTextBlock(
                            spans: [
                                ArticleScreenTextSpan(text: "Вторая "),
                                ArticleScreenTextSpan(
                                    text: "цитата",
                                    linkURL: URL(string: "https://example.com/quote")!
                                ),
                                ArticleScreenTextSpan(text: ".")
                            ]
                        )
                    ]
                ),
                .codeBlock("let value = 42\nprint(value)"),
                .divider
            ]
        )
    }

    @Test
    func articleScreenContentRendererPreservesFigureImageAndCaption() {
        let content = ArticleScreenContentState(
            article: makeReaderArticleDTO(
                contentHTML: """
                <figure>
                    <img src="/images/book.png">
                    <figcaption>Обложка <strong>книги</strong></figcaption>
                </figure>
                """,
                canonicalURL: "https://example.com/articles/body"
            )
        )

        #expect(
            content.body.blocks == [
                .image(URL(string: "https://example.com/images/book.png")!),
                .caption(
                    ArticleScreenTextBlock(
                        spans: [
                            ArticleScreenTextSpan(text: "Обложка "),
                            ArticleScreenTextSpan(text: "книги", isStrong: true)
                        ]
                    )
                )
            ]
        )
    }

    @Test
    func articleScreenContentRendererResolvesLazyImageAttributesAndSrcsetCandidates() {
        let content = ArticleScreenContentState(
            article: makeReaderArticleDTO(
                contentHTML: """
                <img src="data:image/gif;base64,placeholder" data-src="images/lazy.png">
                <img srcset="small.png 320w, large.png 960w">
                <img data-original="/images/original.png">
                """,
                articleURL: "https://example.com/articles/body/index.html",
                canonicalURL: "https://canonical.example.com/article"
            )
        )

        #expect(
            content.body.blocks == [
                .image(URL(string: "https://example.com/articles/body/images/lazy.png")!),
                .image(URL(string: "https://example.com/articles/body/large.png")!),
                .image(URL(string: "https://example.com/images/original.png")!)
            ]
        )
    }

    @Test
    func articleScreenContentRendererResolvesPictureImgFallbackBeforeSourceSrcset() {
        let content = ArticleScreenContentState(
            article: makeReaderArticleDTO(
                contentHTML: """
                <picture>
                    <source media="(min-width: 800px)" srcset="/images/hero-large.jpg 2x, /images/hero-retina.jpg 3x">
                    <img src="/images/hero-small.jpg">
                </picture>
                """
            )
        )

        #expect(
            content.body.blocks == [
                .image(URL(string: "https://example.com/images/hero-small.jpg")!)
            ]
        )
    }

    @Test
    func articleScreenContentRendererSkipsSVGImagesThatUIImageCannotDecode() {
        let content = ArticleScreenContentState(
            article: makeReaderArticleDTO(
                contentHTML: """
                <p>Начать бесплатно</p>
                <img src="/assets/icon.svg">
                """
            )
        )

        #expect(
            content.body.blocks == [
                .paragraph(.plainText("Начать бесплатно"))
            ]
        )
    }

    @Test
    func articleScreenContentRendererRendersVideoLikeImageSourceAsFallbackLink() {
        let content = ArticleScreenContentState(
            article: makeReaderArticleDTO(
                contentHTML: """
                <p>«Вкалывают роботы, а не человек»</p>
                <img src="https://cdn.example.com/video/figure-shift.mp4">
                """
            )
        )

        #expect(
            content.body.blocks == [
                .paragraph(.plainText("«Вкалывают роботы, а не человек»")),
                .paragraph(
                    ArticleScreenTextBlock(
                        spans: [
                            ArticleScreenTextSpan(
                                text: ReadingLocalization.openVideoAction,
                                linkURL: URL(string: "https://cdn.example.com/video/figure-shift.mp4")!
                            )
                        ]
                    )
                )
            ]
        )
    }

    @Test
    func articleScreenContentRendererRendersVideoLikeLeadImageAsFallbackLink() {
        let content = ArticleScreenContentState(
            article: makeReaderArticleDTO(
                contentHTML: "<p>Body copy</p>",
                imageURL: "https://cdn.example.com/video/lead-video.webm"
            )
        )

        #expect(
            content.body.blocks == [
                .paragraph(
                    ArticleScreenTextBlock(
                        spans: [
                            ArticleScreenTextSpan(
                                text: ReadingLocalization.openVideoAction,
                                linkURL: URL(string: "https://cdn.example.com/video/lead-video.webm")!
                            )
                        ]
                    )
                ),
                .paragraph(.plainText("Body copy"))
            ]
        )
    }

    @Test
    func articleScreenContentRendererRemovesNonReadableStyleScriptAndSVGBlocks() {
        let content = ArticleScreenContentState(
            article: makeReaderArticleDTO(
                contentHTML: """
                <p>Всё, продолжаем про аванс.</p>
                <div class="wp-block-lazyblock-banners-btn">
                    <a href="https://practicum.yandex.ru/content-marketer/">
                        Стать контент-маркетологом
                        <svg viewBox="0 0 11 12"><path d="M9 8"></path></svg>
                    </a>
                    <style>
                    .wp-block-lazyblock-banners-btn .article-ban-btn {
                        font-family: NeueMachina, sans-serif;
                    }
                    </style>
                    <script>window.trackBanner()</script>
                </div>
                """
            )
        )

        #expect(
            content.body.blocks == [
                .paragraph(.plainText("Всё, продолжаем про аванс.")),
                .paragraph(
                    ArticleScreenTextBlock(
                        spans: [
                            ArticleScreenTextSpan(
                                text: "Стать контент-маркетологом",
                                linkURL: URL(string: "https://practicum.yandex.ru/content-marketer/")!
                            )
                        ]
                    )
                )
            ]
        )
    }

    @Test
    func articleScreenContentRendererBuildsReadableFallbackLinksForUnsupportedEmbeds() {
        let content = ArticleScreenContentState(
            article: makeReaderArticleDTO(
                contentHTML: """
                <iframe src="https://www.youtube.com/embed/video-id"></iframe>
                <video src="/media/movie.mp4"></video>
                <audio data-src="/media/audio.mp3"></audio>
                <embed src="/media/widget">
                """
            )
        )

        #expect(
            content.body.blocks == [
                .paragraph(
                    ArticleScreenTextBlock(
                        spans: [
                            ArticleScreenTextSpan(
                                text: ReadingLocalization.openEmbeddedContentAction,
                                linkURL: URL(string: "https://www.youtube.com/embed/video-id")!
                            )
                        ]
                    )
                ),
                .paragraph(
                    ArticleScreenTextBlock(
                        spans: [
                            ArticleScreenTextSpan(
                                text: ReadingLocalization.openVideoAction,
                                linkURL: URL(string: "https://example.com/media/movie.mp4")!
                            )
                        ]
                    )
                ),
                .paragraph(
                    ArticleScreenTextBlock(
                        spans: [
                            ArticleScreenTextSpan(
                                text: ReadingLocalization.openAudioAction,
                                linkURL: URL(string: "https://example.com/media/audio.mp3")!
                            )
                        ]
                    )
                ),
                .paragraph(
                    ArticleScreenTextBlock(
                        spans: [
                            ArticleScreenTextSpan(
                                text: ReadingLocalization.openMediaAction,
                                linkURL: URL(string: "https://example.com/media/widget")!
                            )
                        ]
                    )
                )
            ]
        )
    }

    @Test
    func articleScreenContentRendererFallsBackToReadableTextForSimpleTables() {
        let content = ArticleScreenContentState(
            article: makeReaderArticleDTO(
                contentHTML: """
                <table>
                    <tr><th>Платёж</th><th>Дата</th></tr>
                    <tr><td>Аванс</td><td>15 мая</td></tr>
                </table>
                """
            )
        )

        #expect(
            content.body.blocks == [
                .paragraph(.plainText("Платёж Дата Аванс 15 мая"))
            ]
        )
    }
}
