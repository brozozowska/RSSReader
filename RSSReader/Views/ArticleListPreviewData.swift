import SwiftUI

#Preview("Loading") {
    ArticleListPreviewContainer(
        screenState: .previewLoading(
            selection: .unread,
            navigationTitle: "Unread",
            navigationSubtitle: "46 Unread Items"
        )
    )
}

#Preview("Articles Multi-Day") {
    ArticleListPreviewContainer(
        screenState: .previewLoaded(
            selection: .unread,
            navigationTitle: "Unread",
            navigationSubtitle: "7 Unread Items",
            articles: ArticleListPreviewData.multiDayArticles
        )
    )
}

#Preview("Loading Error") {
    ArticleListPreviewContainer(
        screenState: .previewFailed(
            selection: .unread,
            navigationTitle: "Unread",
            navigationSubtitle: "0 Unread Items",
            message: "The selected source could not be loaded from persistence."
        )
    )
}

private struct ArticleListPreviewContainer: View {
    let screenState: ArticlesScreenState
    @State private var selection: UUID? = nil

    var body: some View {
        NavigationStack {
            ArticleListView(
                selectedSidebarSelection: .unread,
                selectedSourcesFilter: .unread,
                reloadID: UUID(),
                showsBackButton: true,
                navigateBackToSources: {},
                previewScreenState: screenState,
                selection: $selection
            )
        }
        .environment(AppState())
    }
}

private enum ArticleListPreviewData {
    static var multiDayArticles: [ArticleListItemDTO] {
        let calendar = Calendar.current
        let now = Date()

        let todayMorning = calendar.date(bySettingHour: 7, minute: 12, second: 0, of: now) ?? now
        let todayEarlier = calendar.date(bySettingHour: 6, minute: 25, second: 0, of: now) ?? now
        let yesterdayBase = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        let yesterdayLate = calendar.date(bySettingHour: 23, minute: 54, second: 0, of: yesterdayBase) ?? yesterdayBase
        let yesterdayEvening = calendar.date(bySettingHour: 21, minute: 31, second: 0, of: yesterdayBase) ?? yesterdayBase
        let olderBase = calendar.date(byAdding: .day, value: -2, to: now) ?? now
        let olderEvening = calendar.date(bySettingHour: 17, minute: 32, second: 0, of: olderBase) ?? olderBase
        let olderAfternoon = calendar.date(bySettingHour: 15, minute: 21, second: 0, of: olderBase) ?? olderBase

        return [
            makeArticle(
                feedTitle: "T-Ж",
                title: "Занимайтесь с отягощением минимум дважды в неделю: совет тренера",
                summary: "Краткий пересказ ключевой новости за сегодня, чтобы на экране было видно вторую строку.",
                publishedAt: todayMorning
            ),
            makeArticle(
                feedTitle: "T-Ж",
                title: "Чешме: что нужно знать перед поездкой",
                summary: "Ещё один короткий анонс статьи, который останется в пределах двух строк.",
                publishedAt: todayEarlier
            ),
            makeArticle(
                feedTitle: "N+1",
                title: "Экипаж Ориона сфотографировал ночную Землю на пути к Луне",
                summary: "Материал за вчера, чтобы следующая секция была заметна в превью.",
                publishedAt: yesterdayLate
            ),
            makeArticle(
                feedTitle: "N+1",
                title: "Древнейшие лошади из Китая оказались ослами",
                summary: "Вторая статья в секции вчерашних публикаций.",
                publishedAt: yesterdayEvening
            ),
            makeArticle(
                feedTitle: "Журнал «Код»",
                title: "У Сбера, Т-Банка и ВТБ массовый сбой",
                summary: "Статья для более старой даты, где позже появится форматированный header с датой.",
                publishedAt: olderEvening
            ),
            makeArticle(
                feedTitle: "N+1",
                title: "FDA одобрило первый низкомолекулярный оральный агонист ГПП-1 для снижения массы тела",
                summary: "Ещё один пример из более старой секции списка.",
                publishedAt: olderAfternoon
            )
        ]
    }

    private static func makeArticle(
        feedTitle: String,
        title: String,
        summary: String,
        publishedAt: Date
    ) -> ArticleListItemDTO {
        ArticleListItemDTO(
            id: UUID(),
            feedID: UUID(),
            feedTitle: feedTitle,
            articleExternalID: UUID().uuidString,
            title: title,
            summary: summary,
            author: nil,
            publishedAt: publishedAt,
            fetchedAt: publishedAt,
            isRead: false,
            isStarred: false,
            isHidden: false
        )
    }
}
