import Foundation
import Testing
@testable import RSSReader

@Suite("Articles Screen / Presentation")
@MainActor
struct ArticlesScreenPresentationTests {
    @Test
    func articleRowSwipeActionsStateReflectsReadAndStarredStatus() {
        let unreadUnstarred = ArticleRowSwipeActionsState(
            article: makeArticleListItemDTO(isRead: false, isStarred: false)
        )
        let readStarred = ArticleRowSwipeActionsState(
            article: makeArticleListItemDTO(isRead: true, isStarred: true)
        )

        #expect(unreadUnstarred.readActionTitle == "Read")
        #expect(unreadUnstarred.readActionSystemImage == "circle")
        #expect(unreadUnstarred.starActionTitle == "Star")
        #expect(unreadUnstarred.starActionSystemImage == "star")

        #expect(readStarred.readActionTitle == "Unread")
        #expect(readStarred.readActionSystemImage == "circle.slash")
        #expect(readStarred.starActionTitle == "Unstar")
        #expect(readStarred.starActionSystemImage == "star.slash")
    }

    @Test
    func articlesScreenNavigationTitleResolverBuildsTitlesFromSidebarSelection() {
        #expect(ArticlesScreenNavigationTitleResolver.resolve(selection: nil) == "Articles")
        #expect(ArticlesScreenNavigationTitleResolver.resolve(selection: .inbox) == "All Items")
        #expect(ArticlesScreenNavigationTitleResolver.resolve(selection: .unread) == "Unread")
        #expect(ArticlesScreenNavigationTitleResolver.resolve(selection: .starred) == "Starred")
        #expect(ArticlesScreenNavigationTitleResolver.resolve(selection: .folder("Tech")) == "Tech")
        #expect(
            ArticlesScreenNavigationTitleResolver.resolve(
                selection: .feed(UUID()),
                selectedFeedTitle: "The Verge"
            ) == "The Verge"
        )
        #expect(ArticlesScreenNavigationTitleResolver.resolve(selection: .feed(UUID())) == "Source")
    }

    @Test
    func articlesScreenSubtitleResolverBuildsSubtitleFromSourcesFilter() {
        let unreadItem = makeArticleListItemDTO(isRead: false, isStarred: false)
        let starredItem = makeArticleListItemDTO(isRead: true, isStarred: true)
        let unreadStarredItem = makeArticleListItemDTO(isRead: false, isStarred: true)
        let articles = [unreadItem, starredItem, unreadStarredItem]

        #expect(
            ArticlesScreenSubtitleResolver.resolve(
                articles: articles,
                sourcesFilter: .allItems
            ) == "2 Unread Items"
        )
        #expect(
            ArticlesScreenSubtitleResolver.resolve(
                articles: articles,
                sourcesFilter: .unread
            ) == "2 Unread Items"
        )
        #expect(
            ArticlesScreenSubtitleResolver.resolve(
                articles: articles,
                sourcesFilter: .starred
            ) == "2 Starred Items"
        )
    }

    @Test
    func articlesDaySectionsBuilderGroupsArticlesByDayAndPreservesVisibleOrder() {
        let calendar = Calendar.current
        let now = Date()
        let todayMorning = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: now) ?? now
        let todayEarlier = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: now) ?? now
        let yesterdayBase = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        let yesterdayArticleDate = calendar.date(bySettingHour: 23, minute: 0, second: 0, of: yesterdayBase) ?? yesterdayBase

        let firstToday = makeArticleListItemDTO(title: "Today One", publishedAt: todayMorning)
        let secondToday = makeArticleListItemDTO(title: "Today Two", publishedAt: todayEarlier)
        let yesterdayArticle = makeArticleListItemDTO(title: "Yesterday", publishedAt: yesterdayArticleDate)

        let sections = ArticlesDaySectionsBuilder.build(
            from: [firstToday, secondToday, yesterdayArticle],
            calendar: calendar
        )

        #expect(sections.count == 2)
        #expect(sections[0].articles.map(\.title) == ["Today One", "Today Two"])
        #expect(sections[1].articles.map(\.title) == ["Yesterday"])
    }

    @Test
    func articlesDaySectionsBuilderBuildsTodayYesterdayAndDateHeaders() {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let older = calendar.date(byAdding: .day, value: -2, to: today) ?? today

        #expect(ArticlesDaySectionsBuilder.title(for: today, calendar: calendar) == "Today")
        #expect(ArticlesDaySectionsBuilder.title(for: yesterday, calendar: calendar) == "Yesterday")
        #expect(
            ArticlesDaySectionsBuilder.title(for: older, calendar: calendar)
            == older.formatted(
                .dateTime
                    .weekday(.wide)
                    .day()
                    .month(.wide)
                    .year()
            )
        )
    }
}
