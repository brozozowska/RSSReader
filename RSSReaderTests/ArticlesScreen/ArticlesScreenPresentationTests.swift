import Foundation
import SwiftUI
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

        #expect(unreadUnstarred.readActionTitle == ReadingLocalization.readAction)
        #expect(unreadUnstarred.readActionSystemImage == "circle")
        #expect(unreadUnstarred.starActionTitle == ReadingLocalization.starAction)
        #expect(unreadUnstarred.starActionSystemImage == "star")

        #expect(readStarred.readActionTitle == ReadingLocalization.unreadAction)
        #expect(readStarred.readActionSystemImage == "circle.slash")
        #expect(readStarred.starActionTitle == ReadingLocalization.unstarAction)
        #expect(readStarred.starActionSystemImage == "star.slash")
    }

    @Test
    func articleRowSwipeActionsUseSemanticRTLReadyEdges() {
        #expect(ArticleRowSwipeActionsState.readStatusEdge == .leading)
        #expect(ArticleRowSwipeActionsState.starredStatusEdge == .trailing)
    }

    @Test
    func articleListRowContentUsesArticleTitleAsPrimaryTextAndSummaryAsPreview() {
        let content = ArticleListRowContent(
            article: makeArticleListItemDTO(
                title: "Создатели Flipper Zero анонсировали Flipper One",
                summary: """
                <p>Это уже другой уровень</p>
                <p>Сообщение <a href="https://thecode.media/article">Создатели Flipper Zero</a> появились сначала.</p>
                """
            )
        )

        #expect(content.titleText == "Создатели Flipper Zero анонсировали Flipper One")
        #expect(content.previewText == "Это уже другой уровень Сообщение Создатели Flipper Zero появились сначала.")
    }

    @Test
    func articleListRowContentDecodesEscapedHTMLPreviewAndSuppressesDuplicateTitlePreview() {
        let escapedHTMLContent = ArticleListRowContent(
            article: makeArticleListItemDTO(
                title: "Что такое аванс",
                summary: "&lt;p&gt;Аванс &amp; зарплата&lt;/p&gt;"
            )
        )
        let duplicateTitleContent = ArticleListRowContent(
            article: makeArticleListItemDTO(
                title: "Что такое аванс",
                summary: "Что такое аванс"
            )
        )

        #expect(escapedHTMLContent.titleText == "Что такое аванс")
        #expect(escapedHTMLContent.previewText == "Аванс & зарплата")
        #expect(duplicateTitleContent.titleText == "Что такое аванс")
        #expect(duplicateTitleContent.previewText == nil)
    }

    @Test
    func articleListRowContentFallsBackToUntitledArticleForBlankTitle() {
        let content = ArticleListRowContent(
            article: makeArticleListItemDTO(
                title: "   ",
                summary: nil
            )
        )

        #expect(content.titleText == ReadingLocalization.untitledArticleTitle)
        #expect(content.previewText == nil)
    }

    @Test
    func articlesScreenNavigationTitleResolverBuildsTitlesFromSidebarSelection() {
        #expect(ArticlesScreenNavigationTitleResolver.resolve(selection: nil) == ReadingLocalization.articlesTitle)
        #expect(ArticlesScreenNavigationTitleResolver.resolve(selection: .inbox) == ReadingLocalization.allItemsTitle)
        #expect(ArticlesScreenNavigationTitleResolver.resolve(selection: .unread) == ReadingLocalization.unreadTitle)
        #expect(ArticlesScreenNavigationTitleResolver.resolve(selection: .starred) == ReadingLocalization.starredTitle)
        #expect(ArticlesScreenNavigationTitleResolver.resolve(selection: .folder("Tech")) == "Tech")
        #expect(
            ArticlesScreenNavigationTitleResolver.resolve(
                selection: .feed(UUID()),
                selectedFeedTitle: "The Verge"
            ) == "The Verge"
        )
        #expect(ArticlesScreenNavigationTitleResolver.resolve(selection: .feed(UUID())) == ReadingLocalization.feedFallbackTitle)
    }

    @Test
    func articlesScreenSubtitleResolverBuildsSubtitleFromSidebarArticleFilter() {
        let unreadItem = makeArticleListItemDTO(isRead: false, isStarred: false)
        let starredItem = makeArticleListItemDTO(isRead: true, isStarred: true)
        let unreadStarredItem = makeArticleListItemDTO(isRead: false, isStarred: true)
        let articles = [unreadItem, starredItem, unreadStarredItem]

        #expect(ReadingLocalization.unreadItemsLowerBoundSubtitle(count: 2).hasPrefix("≥ "))
        #expect(ReadingLocalization.starredItemsLowerBoundSubtitle(count: 2).hasPrefix("≥ "))
        #expect(
            ArticlesScreenSubtitleResolver.resolve(
                articles: articles,
                sidebarArticleFilter: .allItems
            ) == ReadingLocalization.unreadItemsSubtitle(count: 2)
        )
        #expect(
            ArticlesScreenSubtitleResolver.resolve(
                articles: articles,
                sidebarArticleFilter: .unread
            ) == ReadingLocalization.unreadItemsSubtitle(count: 2)
        )
        #expect(
            ArticlesScreenSubtitleResolver.resolve(
                articles: articles,
                sidebarArticleFilter: .starred
            ) == ReadingLocalization.starredItemsSubtitle(count: 2)
        )
    }

    @Test
    func articlesScreenSubtitleResolverUsesEmptyUnreadCopyForZeroUnreadItems() {
        let readItem = makeArticleListItemDTO(isRead: true, isStarred: false)

        #expect(
            ArticlesScreenSubtitleResolver.resolve(
                articles: [],
                sidebarArticleFilter: .allItems
            ) == ReadingLocalization.noUnreadItemsSubtitle
        )
        #expect(
            ArticlesScreenSubtitleResolver.resolve(
                articles: [readItem],
                sidebarArticleFilter: .unread
            ) == ReadingLocalization.noUnreadItemsSubtitle
        )
        #expect(
            ArticlesScreenSubtitleResolver.resolve(
                articles: [],
                sidebarArticleFilter: .starred
            ) == ReadingLocalization.starredItemsSubtitle(count: 0)
        )
    }

    @Test
    func articlesScreenSubtitleResolverMarksLoadedCountsAsLowerBoundsWhileMorePagesRemain() {
        let unreadItem = makeArticleListItemDTO(isRead: false, isStarred: false)
        let starredItem = makeArticleListItemDTO(isRead: true, isStarred: true)
        let unreadStarredItem = makeArticleListItemDTO(isRead: false, isStarred: true)
        let articles = [unreadItem, starredItem, unreadStarredItem]

        #expect(
            ArticlesScreenSubtitleResolver.resolve(
                articles: articles,
                sidebarArticleFilter: .unread,
                hasMorePages: true
            ) == ReadingLocalization.unreadItemsLowerBoundSubtitle(count: 2)
        )
        #expect(
            ArticlesScreenSubtitleResolver.resolve(
                articles: articles,
                sidebarArticleFilter: .starred,
                hasMorePages: true
            ) == ReadingLocalization.starredItemsLowerBoundSubtitle(count: 2)
        )
    }

    @Test
    func customRefreshStateMapsPullProgressToIndicatorContract() {
        let idleState = ArticlesScreenCustomRefreshState.pulling(progress: -0.1)
        let pullingState = ArticlesScreenCustomRefreshState.pulling(progress: 0.4)
        let readyState = ArticlesScreenCustomRefreshState.pulling(progress: 1.2)
        let refreshingState = ArticlesScreenCustomRefreshState.refreshing

        #expect(idleState == .idle)
        #expect(idleState.showsIndicator == false)
        #expect(idleState.indicatorState == .idle)

        #expect(pullingState.phase == .pulling)
        #expect(pullingState.pullProgress == 0.4)
        #expect(pullingState.showsIndicator)
        #expect(pullingState.indicatorState == .pulling(progress: 0.4))

        #expect(readyState.phase == .ready)
        #expect(readyState.pullProgress == 1)
        #expect(readyState.indicatorState == .ready)

        #expect(refreshingState.phase == .refreshing)
        #expect(refreshingState.showsIndicator)
        #expect(refreshingState.indicatorState == .refreshing)
    }

    @Test
    func articleListCustomRefreshPullPolicyMapsTopOverscrollToProgress() {
        let restingGeometry = ArticleListCustomRefreshGeometry(
            contentOffsetY: -12,
            contentInsetTop: 12
        )
        let partialPullGeometry = ArticleListCustomRefreshGeometry(
            contentOffsetY: -48,
            contentInsetTop: 12
        )
        let readyPullGeometry = ArticleListCustomRefreshGeometry(
            contentOffsetY: -120,
            contentInsetTop: 12
        )

        #expect(
            ArticleListCustomRefreshPullPolicy.progress(
                for: restingGeometry,
                threshold: 72
            ) == 0
        )
        #expect(
            ArticleListCustomRefreshPullPolicy.progress(
                for: partialPullGeometry,
                threshold: 72
            ) == 0.5
        )
        #expect(
            ArticleListCustomRefreshPullPolicy.progress(
                for: readyPullGeometry,
                threshold: 72
            ) == 1
        )
    }

    @Test
    func articleListCustomRefreshReleasePolicyTriggersOnlyWhenReadyPullIsReleased() {
        #expect(
            ArticleListCustomRefreshReleasePolicy.shouldTriggerRefresh(
                wasInteracting: true,
                isInteracting: false,
                customRefreshState: .pulling(progress: 1)
            )
        )
        #expect(
            ArticleListCustomRefreshReleasePolicy.shouldTriggerRefresh(
                wasInteracting: true,
                isInteracting: false,
                customRefreshState: .pulling(progress: 0.5)
            ) == false
        )
        #expect(
            ArticleListCustomRefreshReleasePolicy.shouldTriggerRefresh(
                wasInteracting: false,
                isInteracting: false,
                customRefreshState: .pulling(progress: 1)
            ) == false
        )
        #expect(
            ArticleListCustomRefreshReleasePolicy.shouldTriggerRefresh(
                wasInteracting: true,
                isInteracting: true,
                customRefreshState: .pulling(progress: 1)
            ) == false
        )
    }

    @Test
    func articleListPaginationPrefetchRequiresUserDemandNearListEnd() {
        let nearEndGeometry = ArticleListPaginationGeometry(
            contentHeight: 5_000,
            visibleMaxY: 4_100
        )
        let farFromEndGeometry = ArticleListPaginationGeometry(
            contentHeight: 5_000,
            visibleMaxY: 3_000
        )

        #expect(
            ArticleListPaginationPrefetchPolicy.shouldRequestNextPage(
                geometry: nearEndGeometry,
                hasUserDrivenScrollDemand: true,
                canLoadNextPage: true
            )
        )
        #expect(
            ArticleListPaginationPrefetchPolicy.shouldRequestNextPage(
                geometry: nearEndGeometry,
                hasUserDrivenScrollDemand: false,
                canLoadNextPage: true
            ) == false
        )
        #expect(
            ArticleListPaginationPrefetchPolicy.shouldRequestNextPage(
                geometry: farFromEndGeometry,
                hasUserDrivenScrollDemand: true,
                canLoadNextPage: true
            ) == false
        )
        #expect(
            ArticleListPaginationPrefetchPolicy.shouldRequestNextPage(
                geometry: nearEndGeometry,
                hasUserDrivenScrollDemand: true,
                canLoadNextPage: false
            ) == false
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

        #expect(ArticlesDaySectionsBuilder.title(for: today, calendar: calendar) == ReadingLocalization.todaySectionTitle)
        #expect(ArticlesDaySectionsBuilder.title(for: yesterday, calendar: calendar) == ReadingLocalization.yesterdaySectionTitle)
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
