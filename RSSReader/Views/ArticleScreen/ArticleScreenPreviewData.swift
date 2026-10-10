import SwiftUI

// MARK: - State Previews

#Preview("No Selection") {
    ArticleScreenPreviewContainer(screenState: ArticleScreenState())
}

#Preview("Loading") {
    ArticleScreenPreviewContainer(screenState: .previewLoading())
}

#Preview("Failed") {
    ArticleScreenPreviewContainer(
        screenState: .previewFailed(
            message: "The selected article could not be loaded from persistence."
        )
    )
}

#Preview("Not Found") {
    ArticleScreenPreviewContainer(screenState: .previewNotFound())
}

#Preview("Loaded Long Title") {
    ArticleScreenPreviewContainer(
        screenState: .previewLoaded(article: ArticleScreenPreviewData.longTitleArticle)
    )
}

#Preview("RTL Loaded Long Title") {
    ArticleScreenPreviewContainer(
        screenState: .previewLoaded(article: ArticleScreenPreviewData.longTitleArticle)
    )
    .environment(\.layoutDirection, .rightToLeft)
    .environment(\.locale, Locale(identifier: "ar"))
}

#Preview("Adaptive Table") {
    ArticleScreenAdaptiveTablePreview()
}

#Preview("Adaptive Table Compact", traits: .sizeThatFitsLayout) {
    ArticleScreenAdaptiveTablePreview().frame(width: 390, height: 700)
}

#Preview("Adaptive Table Regular", traits: .sizeThatFitsLayout) {
    ArticleScreenAdaptiveTablePreview().frame(width: 900, height: 700)
}

#Preview("Adaptive Table RTL", traits: .sizeThatFitsLayout) {
    ArticleScreenAdaptiveTablePreview()
        .environment(\.layoutDirection, .rightToLeft)
        .environment(\.locale, Locale(identifier: "ar"))
        .frame(width: 900, height: 700)
}

#Preview("Adaptive Table Accessibility", traits: .sizeThatFitsLayout) {
    ArticleScreenAdaptiveTablePreview()
        .environment(\.dynamicTypeSize, .accessibility3)
        .frame(width: 900, height: 700)
}

#Preview("Loaded Content Text Body") {
    ArticleScreenPreviewContainer(
        screenState: .previewLoaded(article: ArticleScreenPreviewData.contentTextBodyArticle)
    )
}

#Preview("Loaded Summary Body") {
    ArticleScreenPreviewContainer(
        screenState: .previewLoaded(article: ArticleScreenPreviewData.summaryBodyArticle)
    )
}

#Preview("Duplicate Author Metadata") {
    ScrollView {
        ReaderArticleContentView(
            content: ArticleScreenContentState(article: ArticleScreenPreviewData.duplicateAuthorArticle),
            actionHandlers: ArticleScreenActionHandlers(
                toggleReadStatus: {},
                toggleStarredStatus: {},
                openSourceArticle: {},
                bodyLinkTapped: { _ in }
            )
        )
        .padding()
    }
}

#Preview("Accordion") {
    ArticleScreenAccordionPreview()
}

#Preview("Accordion RTL Accessibility") {
    ArticleScreenAccordionPreview()
        .environment(\.layoutDirection, .rightToLeft)
        .environment(\.locale, Locale(identifier: "ar"))
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Mark Theme Text") {
    ArticleScreenMarkPreview()
}

#Preview("Mark RTL Accessibility") {
    ArticleScreenMarkPreview()
        .environment(\.layoutDirection, .rightToLeft)
        .environment(\.locale, Locale(identifier: "ar"))
        .environment(\.dynamicTypeSize, .accessibility3)
}

// MARK: - Preview Container

private struct ArticleScreenMarkPreview: View {
    var body: some View {
        ScrollView {
            ReaderArticleContentView(
                content: ArticleScreenContentState(article: ArticleScreenPreviewData.markArticle),
                actionHandlers: ArticleScreenActionHandlers(
                    toggleReadStatus: {}, toggleStarredStatus: {},
                    openSourceArticle: {}, bodyLinkTapped: { _ in }
                )
            )
            .padding()
        }
    }
}

private struct ArticleScreenAccordionPreview: View {
    var body: some View {
        ScrollView {
            ReaderArticleContentView(
                content: ArticleScreenContentState(article: ArticleScreenPreviewData.accordionArticle),
                actionHandlers: ArticleScreenActionHandlers(
                    toggleReadStatus: {}, toggleStarredStatus: {},
                    openSourceArticle: {}, bodyLinkTapped: { _ in }
                )
            )
            .padding()
        }
    }
}

private struct ArticleScreenPreviewContainer: View {
    let screenState: ArticleScreenState

    var body: some View {
        NavigationStack {
            ReaderView(
                articleID: nil,
                previewScreenState: screenState
            )
            .environment(\.appDependencies, AppDependencies.makeDefault())
            .environment(AppState())
        }
    }
}

private struct ArticleScreenAdaptiveTablePreview: View {
    var body: some View {
        ScrollView {
            ReaderArticleContentView(
                content: ArticleScreenContentState(article: ArticleScreenPreviewData.adaptiveTableArticle),
                actionHandlers: ArticleScreenActionHandlers(
                    toggleReadStatus: {},
                    toggleStarredStatus: {},
                    openSourceArticle: {},
                    bodyLinkTapped: { _ in }
                )
            )
            .padding()
        }
    }
}

// MARK: - Preview Data

private enum ArticleScreenPreviewData {
    static var duplicateAuthorArticle: ReaderArticleDTO {
        makeArticle(
            title: "Newsroom update",
            summary: "The author matches the feed title, so the header shows the feed once.",
            contentText: nil,
            feedTitle: "Apple Newsroom",
            author: "  APPLE\t Newsroom  "
        )
    }

    static var longTitleArticle: ReaderArticleDTO {
        makeArticle(
            title: "У Сбера, Т-Банка и ВТБ массовый сбой, который затронул платежи, переводы и часть операций в мобильных приложениях банков",
            summary: """
            Утром 3 апреля был зафиксирован массовый сбой сразу в нескольких российских банках. Пользователи жаловались на переводы, оплату картой и вход в мобильные приложения.
            """,
            contentText: nil,
            isRead: true
        )
    }

    static var summaryBodyArticle: ReaderArticleDTO {
        makeArticle(
            title: "Короткий материал с summary как основным телом статьи",
            summary: """
            Это пример статьи, в которой feed отдал только summary или summary оказался самым качественным источником текста для embedded reader.

            В таком случае `Article Screen` показывает именно summary, потому что сейчас rendering policy выбирает его первым.
            """,
            contentText: nil
        )
    }

    static var contentTextBodyArticle: ReaderArticleDTO {
        makeArticle(
            title: "Материал с полным contentText в качестве основного текста",
            summary: nil,
            contentText: """
            Это пример статьи, в которой feed отдал не только краткий анонс, а полноценный текст в поле contentText.

            Для embedded reader это более предпочтительный источник, когда summary отсутствует.

            Обычно такое приходит из `content:encoded`, `content` или другого более полного поля внутри XML feed.
            """
        )
    }

    static var adaptiveTableArticle: ReaderArticleDTO {
        ReaderArticleDTO(
            id: UUID(),
            feedID: UUID(),
            feedTitle: "Global Markets",
            feedSiteURL: "https://example.com",
            articleExternalID: UUID().uuidString,
            title: "Quarterly market comparison",
            summary: nil,
            contentHTML: """
            <table>
              <thead><tr><th>Region</th><th>Revenue</th><th>Growth</th><th>Outlook</th></tr></thead>
              <tbody>
                <tr><th>North America</th><td>$12.4 billion</td><td>8.2%</td><td>Stable demand across enterprise and consumer segments</td></tr>
                <tr><th>日本</th><td>¥840 billion</td><td>11.6%</td><td>クラウドサービスの需要が引き続き拡大</td></tr>
                <tr><th>الشرق الأوسط</th><td></td><td>6.1%</td><td>نمو مستقر في الأسواق الإقليمية</td></tr>
                <tr><th></th><td>$1.2 billion</td><td>2.4%</td><td>Region pending</td></tr>
              </tbody>
            </table>
            """,
            contentText: nil,
            author: "Research Desk",
            publishedAt: Date(timeIntervalSince1970: 1_775_358_720),
            updatedAtSource: nil,
            effectiveDate: Date(timeIntervalSince1970: 1_775_358_720),
            articleURL: "https://example.com/markets",
            canonicalURL: "https://example.com/markets",
            imageURL: nil,
            isRead: false,
            isStarred: false,
            isHidden: false
        )
    }

    static var markArticle: ReaderArticleDTO {
        makeArticle(
            title: "Reader text",
            summary: nil,
            contentText: """
            <p>Before <mark>ordinary text &amp; entities</mark> after.</p>
            <p><mark><strong>Bold</strong>, <em>italic</em>, <code>inline code</code> and <a href="https://example.com">a link</a>.</mark></p>
            <p><mark>После разговора ответьте на три вопроса.</mark></p>
            <ul><li><mark>Что получилось на деле?</mark></li><li><mark>Что изменю в следующий раз?</mark></li></ul>
            <p><mark>日本語の文章。 العربية نص للقراءة.</mark></p>
            <p>Before <mark>unclosed markup after.</p>
            <pre>Standalone code block</pre>
            """,
            feedTitle: "Preview", author: ""
        )
    }

    static var accordionArticle: ReaderArticleDTO {
        makeArticle(
            title: "Accordion",
            summary: nil,
            contentText: """
            <div class="wp-block-accordion-item">
            <h3><button aria-controls="preview-panel" aria-expanded="true">Keep a work journal · Ведите рабочий конспект</button></h3>
            <div id="preview-panel"><p>Write down terms and links. Записывайте термины и ссылки.</p>
            <ul><li>Documents · Документы</li><li>Questions · Вопросы</li></ul>
            <details open><summary>参考資料を記録する · التفاصيل والملاحظات</summary><p>日本語の段落と العربية لاختبار اتجاه النص.</p></details>
            </div></div>
            <details><summary>A closed section · Закрытый блок</summary><p>Panel content.</p></details>
            """,
            feedTitle: "Preview", author: ""
        )
    }

    private static func makeArticle(
        title: String,
        summary: String?,
        contentText: String?,
        feedTitle: String = "THECODE.MEDIA",
        author: String = "Юлия Зубарева",
        isRead: Bool = false
    ) -> ReaderArticleDTO {
        ReaderArticleDTO(
            id: UUID(),
            feedID: UUID(),
            feedTitle: feedTitle,
            feedSiteURL: "https://thecode.media",
            articleExternalID: UUID().uuidString,
            title: title,
            summary: summary,
            contentHTML: nil,
            contentText: contentText,
            author: author,
            publishedAt: Date(timeIntervalSince1970: 1_775_358_720),
            updatedAtSource: nil,
            effectiveDate: Date(timeIntervalSince1970: 1_775_358_720),
            articleURL: "https://thecode.media/sber-vtb-tbank-failure",
            canonicalURL: "https://thecode.media/sber-vtb-tbank-failure",
            imageURL: nil,
            isRead: isRead,
            isStarred: false,
            isHidden: false
        )
    }
}
