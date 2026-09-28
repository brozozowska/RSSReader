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
    func articleScreenContentRendererBuildsSemanticModelForSimpleTables() {
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
                .table(
                    ArticleScreenTableBlock(
                        columnHeaders: [.plainText("Платёж"), .plainText("Дата")],
                        headerSource: .explicit,
                        rows: [
                            ArticleScreenTableRow(
                                heading: .plainText("Аванс"),
                                cells: [
                                    ArticleScreenTableCell(
                                        columnHeader: .plainText("Дата"),
                                        content: .plainText("15 мая")
                                    )
                                ]
                            )
                        ]
                    )
                )
            ]
        )
    }

    @Test
    func articleScreenContentRendererKeepsConfirmedArticleTableCellsSeparate() {
        let content = ArticleScreenContentState(
            article: makeReaderArticleDTO(
                contentHTML: """
                <figure class="wp-block-table is-style-stripes" style="font-size:17px">
                    <table class="has-fixed-layout"><tbody><tr>
                        <td><strong><mark>Критерий</mark></strong></td>
                        <td><strong><mark>Экспертный трек</mark></strong></td>
                        <td><strong><mark>Управленческий трек</mark></strong></td>
                    </tr><tr>
                        <td>Главный результат</td>
                        <td>Личная экспертиза</td>
                        <td>Результат команды</td>
                    </tr></tbody></table>
                </figure>
                """
            )
        )

        guard case .table(let table) = content.body.blocks.first else {
            Issue.record("Expected a semantic table block")
            return
        }

        #expect(table.columnHeaders.map { $0?.plainText } == ["Критерий", "Экспертный трек", "Управленческий трек"])
        #expect(table.headerSource == .inferred)
        #expect(table.rows.count == 1)
        #expect(table.rows[0].heading?.plainText == "Главный результат")
        #expect(table.rows[0].cells.map { $0.content?.plainText } == ["Личная экспертиза", "Результат команды"])
    }

    @Test
    func articleScreenContentRendererPreservesInlineFormattingAndLinksInTableCells() {
        let content = ArticleScreenContentState(
            article: makeReaderArticleDTO(
                contentHTML: """
                <table>
                    <tr><th>Тип</th><th>Описание</th></tr>
                    <tr><td><strong>Swift</strong></td><td><em>Читайте</em> <a href="/guide"><code>guide</code></a></td></tr>
                </table>
                """,
                articleURL: "https://example.com/articles/1"
            )
        )

        guard case .table(let table) = content.body.blocks.first,
              let heading = table.rows.first?.heading,
              let value = table.rows.first?.cells.first?.content else {
            Issue.record("Expected formatted semantic table cells")
            return
        }

        #expect(heading.spans.first?.isStrong == true)
        #expect(value.spans.contains { $0.isEmphasized })
        #expect(value.spans.contains {
            $0.isCode && $0.linkURL == URL(string: "https://example.com/guide")
        })
    }

    @Test
    func articleScreenContentRendererUsesStructuredFallbackForMalformedAndSpanningTables() {
        let malformed = ArticleScreenContentState(
            article: makeReaderArticleDTO(
                contentHTML: "<table><tr><th>Заголовок</th></tr><tr><td>Значение</table>"
            )
        )
        let spanning = ArticleScreenContentState(
            article: makeReaderArticleDTO(
                contentHTML: "<table><tr><th colspan=\"2\">Итог</th></tr><tr><td>Один</td><td>Два</td></tr></table>"
            )
        )

        #expect(malformed.body.blocks.map(\.textForTest) == ["Заголовок", "Значение"])
        #expect(spanning.body.blocks.map(\.textForTest) == ["Итог", "Один", "Два"])
    }

    @Test
    func articleScreenContentRendererPreservesEmptyCellsAndHeaderlessColumnOrder() {
        let withEmptyCell = ArticleScreenContentState(
            article: makeReaderArticleDTO(
                contentHTML: "<table><tr><th>Имя</th><th></th><th>Статус</th></tr><tr><td>Анна</td><td></td><td>Готово</td></tr></table>"
            )
        )
        let withoutHeaders = ArticleScreenContentState(
            article: makeReaderArticleDTO(
                contentHTML: "<table><tr><td>Первый</td><td>Второй</td></tr></table>"
            )
        )

        guard case .table(let emptyCellTable) = withEmptyCell.body.blocks.first,
              case .table(let headerlessTable) = withoutHeaders.body.blocks.first else {
            Issue.record("Expected semantic table blocks")
            return
        }

        #expect(emptyCellTable.columnHeaders.count == 3)
        #expect(emptyCellTable.columnHeaders[1] == nil)
        #expect(emptyCellTable.rows[0].cells[0].content == nil)
        #expect(emptyCellTable.rows[0].cells[1].content?.plainText == "Готово")
        #expect(headerlessTable.columnHeaders.isEmpty)
        #expect(headerlessTable.rows[0].cells.map { $0.content?.plainText } == ["Первый", "Второй"])
    }

    @Test
    func articleScreenContentRendererDoesNotTreatAngleBracketTextAsTableMarkup() {
        let content = ArticleScreenContentState(
            article: makeReaderArticleDTO(contentHTML: "<p>Если 2 < 3 и 5 > 4, сравнение верно.</p>")
        )

        #expect(content.body.blocks == [.paragraph(.plainText("Если 2 < 3 и 5 > 4, сравнение верно."))])
    }

    @Test
    func articleScreenContentRendererTreatsStructuralWrappersAsTransparentContainers() {
        for tagName in ["div", "section", "article", "main", "header", "footer"] {
            let content = ArticleScreenContentState(
                article: makeReaderArticleDTO(
                    contentHTML: "<\(tagName)><p>Содержимое \(tagName)</p></\(tagName)>"
                )
            )

            #expect(
                content.body.blocks == [.paragraph(.plainText("Содержимое \(tagName)"))],
                "Expected transparent rendering for <\(tagName)>"
            )
        }
    }

    @Test
    func articleScreenContentRendererPreservesMixedContainerContentInSourceOrder() {
        let content = ArticleScreenContentState(
            article: makeReaderArticleDTO(
                contentHTML: """
                До контейнера
                <section>
                    <h2>Заголовок</h2>
                    <p><em>Абзац</em> <a href="/guide"><code>guide</code></a></p>
                    <ul><li>Первый</li><li>Второй</li></ul>
                    <blockquote>Цитата</blockquote>
                    <pre>let value = 42</pre>
                    <figure><img src="/image.png"><figcaption>Подпись</figcaption></figure>
                    <table><tr><th>Тип</th><th>Значение</th></tr><tr><td>A</td><td>B</td></tr></table>
                    <video src="/movie.mp4"></video>
                </section>
                После контейнера
                """
            )
        )

        #expect(content.body.blocks.count == 11)
        #expect(content.body.blocks[0] == .paragraph(.plainText("До контейнера")))
        #expect(content.body.blocks[1] == .heading(level: 2, .plainText("Заголовок")))
        #expect(content.body.blocks[2].textForTest == "Абзацguide")
        #expect(content.body.blocks[3] == .list(ArticleScreenListBlock(
            kind: .unordered,
            items: [.plainText("Первый"), .plainText("Второй")]
        )))
        #expect(content.body.blocks[4] == .blockquote([.plainText("Цитата")]))
        #expect(content.body.blocks[5] == .codeBlock("let value = 42"))
        #expect(content.body.blocks[6] == .image(URL(string: "https://example.com/image.png")!))
        #expect(content.body.blocks[7] == .caption(.plainText("Подпись")))
        #expect(content.body.blocks[8].isTableForTest)
        #expect(content.body.blocks[9].textForTest == ReadingLocalization.openVideoAction)
        #expect(content.body.blocks[10].textForTest == "После контейнера")

        guard case .paragraph(let linkedParagraph) = content.body.blocks[2] else {
            Issue.record("Expected linked paragraph")
            return
        }
        #expect(linkedParagraph.spans.contains {
            $0.text == "guide"
                && $0.isCode
                && $0.linkURL == URL(string: "https://example.com/guide")
        })
        #expect(linkedParagraph.spans.contains { $0.text == "Абзац" && $0.isEmphasized })
    }

    @Test
    func articleScreenContentRendererDoesNotDuplicateTextAcrossNestedContainers() {
        let content = ArticleScreenContentState(
            article: makeReaderArticleDTO(
                contentHTML: """
                <article>До<div><section><p>Внутри</p></section></div>После</article>
                """
            )
        )

        #expect(content.body.blocks.map(\.textForTest) == ["До", "Внутри", "После"])
    }

    @Test
    func articleScreenContentRendererBoundsDeepAndMalformedContainerTraversal() {
        let deeplyNestedHTML = String(repeating: "<div>", count: 40)
            + "<p>Глубокий текст</p>"
            + String(repeating: "</div>", count: 40)
        let deeplyNested = ArticleScreenContentState(
            article: makeReaderArticleDTO(contentHTML: deeplyNestedHTML)
        )
        let malformed = ArticleScreenContentState(
            article: makeReaderArticleDTO(
                contentHTML: "<div>До<section><p>Сохранено</p></div>После"
            )
        )
        let unknown = ArticleScreenContentState(
            article: makeReaderArticleDTO(
                contentHTML: "<nav>До<p>Внутри</p>После</nav>"
            )
        )

        #expect(deeplyNested.body.blocks.map(\.textForTest) == ["Глубокий текст"])
        #expect(malformed.body.blocks.map(\.textForTest) == ["До", "Сохранено", "После"])
        #expect(unknown.body.blocks.map(\.textForTest) == ["До", "Внутри", "После"])
    }

    @Test
    func articleScreenContentRendererBuildsDefinitionListWithMultipleAndEmptyDefinitions() {
        let content = ArticleScreenContentState(
            article: makeReaderArticleDTO(
                contentHTML: """
                <dl>
                    <dt><strong>API</strong></dt>
                    <dd>Первое <a href="/guide"><code>описание</code></a></dd>
                    <dd></dd>
                    <dt></dt>
                    <dd><em>Без названия</em></dd>
                </dl>
                """
            )
        )

        guard case .definitionList(let definitionList) = content.body.blocks.first else {
            Issue.record("Expected a semantic definition list")
            return
        }

        #expect(definitionList.entries.count == 2)
        #expect(definitionList.entries[0].term?.plainText == "API")
        #expect(definitionList.entries[0].term?.spans.first?.isStrong == true)
        #expect(definitionList.entries[0].definitions.count == 2)
        #expect(definitionList.entries[0].definitions[1] == nil)
        #expect(definitionList.entries[0].definitions[0]?.spans.contains {
            $0.text == "описание"
                && $0.isCode
                && $0.linkURL == URL(string: "https://example.com/guide")
        } == true)
        #expect(definitionList.entries[1].term == nil)
        #expect(definitionList.entries[1].definitions[0]?.spans.first?.isEmphasized == true)
    }

    @Test
    func articleScreenContentRendererBuildsOpenDisclosureWithNestedSemanticContent() {
        let content = ArticleScreenContentState(
            article: makeReaderArticleDTO(
                contentHTML: """
                <details open>
                    <summary><strong>Подробнее</strong></summary>
                    <p>Основной текст</p>
                    <aside><p>Примечание</p></aside>
                    <details><summary>Ещё</summary><p>Вложенный текст</p></details>
                </details>
                """
            )
        )

        guard case .disclosure(let disclosure) = content.body.blocks.first else {
            Issue.record("Expected a semantic disclosure, got \(content.body.blocks)")
            return
        }

        #expect(disclosure.summary.plainText == "Подробнее")
        #expect(disclosure.summary.spans.first?.isStrong == true)
        #expect(disclosure.isInitiallyExpanded)
        #expect(disclosure.content.count == 3)
        #expect(disclosure.content[0].textForTest == "Основной текст")
        guard case .aside(let asideContent) = disclosure.content[1],
              case .disclosure(let nestedDisclosure) = disclosure.content[2] else {
            Issue.record("Expected nested aside and disclosure")
            return
        }
        #expect(asideContent.map(\.textForTest) == ["Примечание"])
        #expect(nestedDisclosure.summary.plainText == "Ещё")
        #expect(nestedDisclosure.isInitiallyExpanded == false)
        #expect(nestedDisclosure.content.map(\.textForTest) == ["Вложенный текст"])
    }

    @Test
    func articleScreenContentRendererPreservesAsideAndAddressInSourceOrder() {
        let content = ArticleScreenContentState(
            article: makeReaderArticleDTO(
                contentHTML: """
                <p>До</p>
                <aside><h3>Важно</h3><p>Проверьте данные</p></aside>
                <address>Автор: <a href="/team"><em>редакция</em></a></address>
                <p>После</p>
                """
            )
        )

        #expect(content.body.blocks.count == 4)
        #expect(content.body.blocks[0].textForTest == "До")
        guard case .aside(let asideContent) = content.body.blocks[1],
              case .address(let address) = content.body.blocks[2] else {
            Issue.record("Expected semantic aside and address, got \(content.body.blocks)")
            return
        }
        #expect(asideContent.count == 2)
        #expect(address.plainText == "Автор: редакция")
        #expect(address.spans.contains {
            $0.text == "редакция"
                && $0.isEmphasized
                && $0.linkURL == URL(string: "https://example.com/team")
        })
        #expect(content.body.blocks[3].textForTest == "После")
    }

    @Test
    func articleScreenContentRendererFallsBackForMalformedStructuredBlocks() {
        let malformedDefinitionList = ArticleScreenContentState(
            article: makeReaderArticleDTO(
                contentHTML: "<dl><dt>Термин</dt><dd>Определение</dl>"
            )
        )
        let disclosureWithoutSummary = ArticleScreenContentState(
            article: makeReaderArticleDTO(
                contentHTML: "<details><p>Доступный текст</p></details>"
            )
        )
        let emptyDisclosure = ArticleScreenContentState(
            article: makeReaderArticleDTO(
                contentHTML: "<details><summary>Только заголовок</summary></details>"
            )
        )
        let outerDisclosureWithoutSummary = ArticleScreenContentState(
            article: makeReaderArticleDTO(
                contentHTML: "<details><p>Внешний текст</p><details><summary>Вложенный</summary><p>Текст</p></details></details>"
            )
        )

        #expect(malformedDefinitionList.body.blocks.map(\.textForTest) == ["Термин", "Определение"])
        #expect(disclosureWithoutSummary.body.blocks.map(\.textForTest) == ["Доступный текст"])
        #expect(emptyDisclosure.body.blocks.map(\.textForTest) == ["Только заголовок"])
        #expect(outerDisclosureWithoutSummary.body.blocks.first?.textForTest == "Внешний текст")
        guard outerDisclosureWithoutSummary.body.blocks.count == 2,
              case .disclosure(let nestedDisclosure) = outerDisclosureWithoutSummary.body.blocks[1] else {
            Issue.record("Expected readable outer fallback and nested disclosure")
            return
        }
        #expect(nestedDisclosure.summary.plainText == "Вложенный")
    }
}

private extension ArticleScreenBodyBlock {
    var textForTest: String? {
        guard case .paragraph(let text) = self else { return nil }
        return text.plainText
    }

    var isTableForTest: Bool {
        guard case .table = self else { return false }
        return true
    }
}
