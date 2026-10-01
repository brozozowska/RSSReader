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

// MARK: - Preview Container

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

    private static func makeArticle(
        title: String,
        summary: String?,
        contentText: String?,
        isRead: Bool = false
    ) -> ReaderArticleDTO {
        ReaderArticleDTO(
            id: UUID(),
            feedID: UUID(),
            feedTitle: "THECODE.MEDIA",
            feedSiteURL: "https://thecode.media",
            articleExternalID: UUID().uuidString,
            title: title,
            summary: summary,
            contentHTML: nil,
            contentText: contentText,
            author: "Юлия Зубарева",
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
