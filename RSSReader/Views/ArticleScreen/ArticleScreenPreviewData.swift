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

#Preview("Loaded Summary Body") {
    ArticleScreenPreviewContainer(
        screenState: .previewLoaded(article: ArticleScreenPreviewData.summaryBodyArticle)
    )
}

#Preview("Loaded Content Text Body") {
    ArticleScreenPreviewContainer(
        screenState: .previewLoaded(article: ArticleScreenPreviewData.contentTextBodyArticle)
    )
}

// MARK: - Preview Container

private struct ArticleScreenPreviewContainer: View {
    let screenState: ArticleScreenState

    var body: some View {
        NavigationStack {
            ReaderView(
                articleID: nil,
                showsBackButton: true,
                navigateBackToArticles: {},
                previewScreenState: screenState
            )
            .environment(\.appDependencies, AppDependencies.makeDefault())
            .environment(AppState())
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
            articleURL: "https://thecode.media/sber-vtb-tbank-failure",
            canonicalURL: "https://thecode.media/sber-vtb-tbank-failure",
            imageURL: nil,
            isRead: isRead,
            isStarred: false,
            isHidden: false
        )
    }
}
