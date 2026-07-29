import Foundation
import SwiftData
import Testing
@testable import RSSReader

@Suite("Articles Screen / Controller / Mark All Read")
@MainActor
struct ArticlesScreenControllerMarkAllReadTests {
    @Test
    func articlesScreenControllerPresentsConfirmationWhenAskBeforeMarkingAllAsReadIsEnabled() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appSettingsRepository = try #require(harness.dependencies.appSettingsRepository)
        let unreadItem = makeArticleListItemDTO(isRead: false, isStarred: false)
        let controller = ArticlesScreenController(
            previewScreenState: .previewLoaded(
                selection: .feed(unreadItem.feedID),
                navigationTitle: "Feed",
                navigationSubtitle: "1 Unread Item",
                articles: [unreadItem]
            )
        )

        _ = try appSettingsRepository.update(
            AppSettingsUpdate(
                askBeforeMarkingAllAsRead: true,
                updatedAt: .distantPast
            )
        )

        controller.handleMarkAllAsReadAction(
            searchText: "",
            selection: .feed(unreadItem.feedID),
            sidebarArticleFilter: .allItems,
            dependencies: harness.dependencies,
            isPreviewMode: false
        )

        #expect(controller.screenState.pendingConfirmation == .markAllAsRead)
        #expect(controller.screenState.articles.first?.isRead == false)
    }

    @Test
    func articlesScreenControllerMarksAllAsReadImmediatelyWhenAskBeforeMarkingAllAsReadIsDisabled() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appSettingsRepository = try #require(harness.dependencies.appSettingsRepository)
        let articleStateRepository = try #require(harness.dependencies.articleStateRepository)
        let unreadItem = makeArticleListItemDTO(isRead: false, isStarred: false)
        let controller = ArticlesScreenController(
            previewScreenState: .previewLoaded(
                selection: .feed(unreadItem.feedID),
                navigationTitle: "Feed",
                navigationSubtitle: "1 Unread Item",
                articles: [unreadItem]
            )
        )

        _ = try appSettingsRepository.update(
            AppSettingsUpdate(
                askBeforeMarkingAllAsRead: false,
                updatedAt: .distantPast
            )
        )

        controller.handleMarkAllAsReadAction(
            searchText: "",
            selection: .feed(unreadItem.feedID),
            sidebarArticleFilter: .allItems,
            dependencies: harness.dependencies,
            isPreviewMode: false
        )

        let persistedState = try articleStateRepository.fetchStateSnapshot(
            feedID: unreadItem.feedID,
            articleExternalID: unreadItem.articleExternalID
        )

        #expect(controller.screenState.pendingConfirmation == nil)
        #expect(controller.screenState.articles.first?.isRead == true)
        #expect(controller.screenState.navigationSubtitle == ReadingLocalization.noUnreadItemsSubtitle)
        #expect(persistedState?.isRead == true)
    }

    @Test
    func articlesScreenControllerMarksAccumulatedPagesAndPreservesContinuationCursor() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let first = makeArticleListItemDTO(
            articleExternalID: "mark-page-first",
            isRead: false,
            isStarred: false
        )
        let second = makeArticleListItemDTO(
            feedID: first.feedID,
            articleExternalID: "mark-page-second",
            isRead: false,
            isStarred: false
        )
        let nextCursor = ArticleSearchRequest.Cursor(repositoryOffset: 2)
        var screenState = ArticlesScreenState()
        screenState.applyLoadedArticles(
            [first, second],
            selection: .feed(first.feedID),
            navigationTitle: "Feed",
            navigationSubtitle: ReadingLocalization.unreadItemsSubtitle(count: 2),
            sessionContext: ArticleListSession.Context(
                selection: .feed(first.feedID),
                sidebarArticleFilter: .allItems
            ),
            nextPageCursor: nextCursor
        )
        let controller = ArticlesScreenController(previewScreenState: screenState)

        controller.confirmMarkAllAsRead(
            searchText: "",
            selection: .feed(first.feedID),
            sidebarArticleFilter: .allItems,
            dependencies: harness.dependencies,
            isPreviewMode: true
        )

        #expect(controller.screenState.articles.allSatisfy { $0.isRead })
        #expect(controller.screenState.articleListSession.nextPageCursor == nextCursor)
        #expect(
            controller.screenState.navigationSubtitle
                == ReadingLocalization.unreadItemsLowerBoundSubtitle(count: 0)
        )
    }
}
