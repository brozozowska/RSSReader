import Foundation
import Testing
import UIKit
@testable import RSSReader

@Suite("Article Screen / Content Rendering")
@MainActor
struct ArticleScreenContentRendererTests {
    @Test
    func articleScreenContentHeaderFormatsFieldsInPublishedTitleAuthorFeedOrder() {
        let publishedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let content = ArticleScreenContentState(
            article: makeReaderArticleDTO(
                feedTitle: "THECODE.MEDIA",
                author: "Юлия Зубарева",
                publishedAt: publishedAt
            )
        )

        #expect(content.header.publishedAtText == ArticleScreenDateFormatter.string(from: publishedAt))
        #expect(content.header.title == "Article")
        #expect(content.header.author == "Юлия Зубарева")
        #expect(content.header.feedTitle == "THECODE.MEDIA")
    }

    @Test
    func articleScreenContentHeaderHidesBlankMetadataAndFallsBackForBlankTitle() {
        let content = ArticleScreenContentState(
            article: makeReaderArticleDTO(
                feedTitle: "   ",
                title: "   ",
                author: " \n ",
                publishedAt: nil
            )
        )

        #expect(content.header.publishedAtText == nil)
        #expect(content.header.title == "Untitled Article")
        #expect(content.header.author == nil)
        #expect(content.header.feedTitle == nil)
    }

    @Test
    func articleScreenStateUsesExistingRenderingPriorityForBodyContent() {
        var state = ArticleScreenState()
        let article = makeReaderArticleDTO(
            summary: "Summary copy",
            contentHTML: "<p>HTML body</p>",
            contentText: "Longer content text"
        )

        state.applyLoadedArticle(article)

        #expect(state.derivedViewState().content?.body.blocks == [.paragraph(.plainText("HTML body"))])
        #expect(state.derivedViewState().content?.body.source == .contentHTML)
    }

    @Test
    func articleScreenBodyPayloadNormalizerClassifiesEscapedHTMLAsHTML() throws {
        let payload = try #require(
            ArticleScreenBodyPayloadNormalizer.normalize(
                """
                &lt;p&gt;Это уже другой уровень&lt;/p&gt;
                &lt;p&gt;Сообщение &lt;a href=&quot;https://thecode.media/article&quot;&gt;Создатели Flipper Zero&lt;/a&gt; появились сначала&lt;/p&gt;
                """,
                preferredKind: .plainText
            )
        )

        #expect(payload.kind == .html)
        #expect(payload.value.contains("<p>Это уже другой уровень</p>"))
        #expect(payload.value.contains(#"<a href="https://thecode.media/article">Создатели Flipper Zero</a>"#))
    }

    @Test
    func articleScreenBodyPayloadNormalizerDecodesNumericEntities() throws {
        let payload = try #require(
            ArticleScreenBodyPayloadNormalizer.normalize(
                "Зарплата &#8381; и аванс &#x20BD;",
                preferredKind: .plainText
            )
        )

        #expect(payload.kind == .plainText)
        #expect(payload.value == "Зарплата ₽ и аванс ₽")
    }

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
                                text: "Open video",
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
                                text: "Open video",
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
                                text: "Open embedded content",
                                linkURL: URL(string: "https://www.youtube.com/embed/video-id")!
                            )
                        ]
                    )
                ),
                .paragraph(
                    ArticleScreenTextBlock(
                        spans: [
                            ArticleScreenTextSpan(
                                text: "Open video",
                                linkURL: URL(string: "https://example.com/media/movie.mp4")!
                            )
                        ]
                    )
                ),
                .paragraph(
                    ArticleScreenTextBlock(
                        spans: [
                            ArticleScreenTextSpan(
                                text: "Open audio",
                                linkURL: URL(string: "https://example.com/media/audio.mp3")!
                            )
                        ]
                    )
                ),
                .paragraph(
                    ArticleScreenTextBlock(
                        spans: [
                            ArticleScreenTextSpan(
                                text: "Open media",
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
                .fallbackNotice("This source only provides a summary, not the full article body.")
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
                .fallbackNotice("This source only provides a summary, not the full article body.")
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
                .fallbackNotice("Full article content is unavailable in this feed.")
            ]
        )
        #expect(content.body.source == .empty)
    }

    @Test
    func articleImageMemoryCacheStoresDecodedImagesByURL() throws {
        let cache = ArticleImageMemoryCache(countLimit: 2, totalCostLimit: 1_024)
        let imageURL = URL(string: "https://example.com/article-image.png")!
        let otherURL = URL(string: "https://example.com/other-image.png")!
        let image = makeTestImage()

        cache.insert(image, for: imageURL, cost: 16)
        let cachedImage = try #require(cache.image(for: imageURL))

        #expect(cachedImage === image)
        #expect(cache.image(for: otherURL) == nil)
    }

    @Test
    func articleImageMemoryCacheCanBeCleared() {
        let cache = ArticleImageMemoryCache(countLimit: 2, totalCostLimit: 1_024)
        let imageURL = URL(string: "https://example.com/article-image.png")!

        cache.insert(makeTestImage(), for: imageURL, cost: 16)
        cache.removeAllImages()

        #expect(cache.image(for: imageURL) == nil)
    }

    @Test
    func cachedArticleImageLayoutPolicyDoesNotUpscaleSmallImages() {
        let layout = CachedArticleImageLayoutPolicy.layout(for: CGSize(width: 120, height: 80))

        #expect(layout.maxImageWidth == 120)
        #expect(layout.horizontalAlignment == .center)
    }

    @Test
    func cachedArticleImageLayoutPolicyKeepsLargeImagesAdaptive() {
        let layout = CachedArticleImageLayoutPolicy.layout(for: CGSize(width: 1_200, height: 800))

        #expect(layout.maxImageWidth == nil)
        #expect(layout.horizontalAlignment == .center)
    }

    private func makeTestImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        return renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
    }
}
