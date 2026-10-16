import SwiftUI
import Testing
import UIKit
@testable import RSSReader

@Suite("Articles Screen / Reader Follow", .serialized)
@MainActor
struct ArticlesScreenReaderFollowTests {
    @Test(arguments: [false, true])
    func readerNavigationRevealsOnlyOutOfViewRowsInBothDirections(covered: Bool) async throws {
        try await exerciseReaderVisibility(covered: covered)
    }

    @Test
    func accessibilityAndRTLUseActualRowGeometry() async throws {
        try await exerciseReaderVisibility(covered: true, accessibility: true)
    }

    private func exerciseReaderVisibility(covered: Bool, accessibility: Bool = false) async throws {
        let articles = (0..<100).map { index in
            makeArticleListItemDTO(
                title: "Article \(index)",
                summary: index.isMultiple(of: 3)
                    ? "A longer preview that makes this row taller than its neighbours. This text wraps over several lines."
                    : nil,
                publishedAt: Date(timeIntervalSince1970: 10_000 - Double(index))
            )
        }
        let appState = AppState()
        appState.selectSidebarSelection(.inbox)
        appState.updateArticleNavigationContext(
            articles.map(\.id),
            sidebarSelection: .inbox,
            sidebarArticleFilter: .allItems,
            articleListSessionID: UUID()
        )
        let coordinator = ArticleListReaderScrollCoordinator()
        let sessionID = appState.currentArticleListSessionReference!.id
        let sections = ArticlesDaySectionsBuilder.build(from: articles)
        func navigate(_ direction: ReaderAdjacentArticleNavigationDirection) {
            #expect(appState.selectAdjacentArticle(direction))
            coordinator.reveal(appState.selectedArticleID!, direction: direction, sessionID: sessionID, sections: sections)
        }
        let host = UIHostingController(rootView: ReaderFollowListFixture(
            appState: appState,
            articles: articles,
            coordinator: coordinator,
            sessionID: sessionID
        ))
        let navigation = UINavigationController(rootViewController: host)
        if accessibility {
            navigation.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
            navigation.view.semanticContentAttribute = .forceRightToLeft
        }
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = navigation
        window.isHidden = false
        defer { window.isHidden = true }
        await settle(host)
        let list = try #require(findList(in: host.view))
        #expect(list.numberOfItems(inSection: 0) == 100)
        let initialOffset = list.contentOffset.y
        let nextRow = try #require(list.layoutAttributesForItem(at: IndexPath(item: 1, section: 0)))
        let nextRowFits = list.bounds.inset(by: list.adjustedContentInset).contains(nextRow.frame)

        appState.selectArticle(articles[0].id)
        if covered {
            navigation.pushViewController(UIViewController(), animated: false)
        }
        await settle(host)
        navigate(.next)
        await settle(host)
        if nextRowFits {
            #expect(abs(list.contentOffset.y - initialOffset) < 1)
        }

        for _ in 2...70 {
            navigate(.next)
            await settle(host)
        }
        if covered {
            navigation.popViewController(animated: false)
            host.view.layoutIfNeeded()
        }
        let target = try #require(list.layoutAttributesForItem(at: IndexPath(item: 70, section: 0)))
        let viewport = list.bounds.inset(by: list.adjustedContentInset)
        #expect(abs(target.frame.maxY - viewport.maxY) < 2)
        let followedOffset = list.contentOffset.y
        await settle(host)
        #expect(abs(list.contentOffset.y - followedOffset) < 1)

        for _ in 0..<65 {
            navigate(.previous)
            await settle(host)
        }
        let previousTarget = try #require(list.layoutAttributesForItem(at: IndexPath(item: 5, section: 0)))
        let previousViewport = list.bounds.inset(by: list.adjustedContentInset)
        let header = list.collectionViewLayout.layoutAttributesForSupplementaryView(
            ofKind: UICollectionView.elementKindSectionHeader, at: IndexPath(item: 0, section: 0)
        )
        #expect(abs(previousTarget.frame.minY - previousViewport.minY - (header?.frame.height ?? 0)) < 2)
    }

    @Test
    func readerCrossesPageBoundaryAndReturnsToCurrentRowWithoutListDrivenLoads() async throws {
        for filter: SidebarArticleFilter in [.allItems, .unread, .starred] {
            try await exerciseReaderPageBoundary(filter: filter)
        }
        try await exerciseReaderPageBoundary(filter: .unread, ascending: true, searchText: "article")
    }

    private func exerciseReaderPageBoundary(
        filter: SidebarArticleFilter, ascending: Bool = false, searchText: String = ""
    ) async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/reader-follow.xml"]).first)
        if ascending {
            let settings = try #require(harness.dependencies.appSettingsRepository)
            _ = try settings.update(AppSettingsUpdate(unreadArticleSortMode: .publishedAtAscending))
        }
        let articles = (0..<130).map { index in
            makeArticleListItemDTO(
                feedID: feed.id,
                articleExternalID: "follow-\(index)",
                title: "Article \(index)",
                publishedAt: Date(timeIntervalSince1970: 10_000 + Double(ascending ? index : -index)),
                isRead: false,
                isStarred: true
            )
        }
        let cursor1 = makeArticleSearchCursor(seed: 1)
        let cursor2 = makeArticleSearchCursor(seed: 2)
        var requests = 0
        var listDrivenLoads = 0
        let controller = ArticlesScreenController(searchQueryOperation: { request, _ in
            requests += 1
            if request.cursor == nil {
                return ArticleSearchResultSnapshot(articles: Array(articles.prefix(50)), hasScopeContent: true, nextCursor: cursor1)
            }
            if request.cursor == cursor1 {
                return ArticleSearchResultSnapshot(articles: Array(articles[50..<100]), hasScopeContent: true, nextCursor: cursor2)
            }
            return ArticleSearchResultSnapshot(articles: Array(articles[100..<130]), hasScopeContent: true)
        })
        let appState = AppState()
        appState.selectSidebarSelection(.feed(feed.id))
        appState.selectSidebarArticleFilter(filter)
        await controller.load(selection: .feed(feed.id), sidebarArticleFilter: filter, searchText: searchText, dependencies: harness.dependencies)
        #expect(controller.screenState.articleListSession.context.normalizedSearchText == searchText)
        #expect(controller.screenState.articleListSession.context.sortMode == (ascending ? .publishedAtAscending : .publishedAtDescending))
        let sessionID = controller.currentArticleListSessionID
        appState.updateArticleNavigationContext(
            controller.visibleArticleIDs(), sidebarSelection: .feed(feed.id),
            sidebarArticleFilter: filter, articleListSessionID: sessionID
        )
        let host = UIHostingController(rootView: ReaderFollowListFixture(
            appState: appState, articles: [], coordinator: controller.readerScrollCoordinator,
            sessionID: sessionID, controller: controller,
            loadNextPageAction: { listDrivenLoads += 1 }
        ))
        let navigation = UINavigationController(rootViewController: host)
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = navigation
        window.isHidden = false
        defer { window.isHidden = true }
        await settle(host)
        let list = try #require(findList(in: host.view))
        #expect(list.numberOfItems(inSection: 0) == 50)
        appState.selectArticle(articles[0].id)
        navigation.pushViewController(UIViewController(), animated: false)
        for index in 1...70 {
            controller.markArticleAsReadInCurrentSession(articles[index - 1].id)
            await ArticleListContinuationCoordinator.prefetchNextPageIfNeeded(
                minimumNextArticleCount: 6, appState: appState, controller: controller, dependencies: harness.dependencies
            )
            #expect(appState.selectAdjacentArticle(.next))
            controller.followReaderArticle(
                appState.selectedArticleID!, direction: .next, in: appState.currentArticleListSessionReference
            )
            await settle(host)
        }
        #expect(requests == 2)
        #expect(listDrivenLoads == 0)
        #expect(controller.screenState.articles.count == 100)
        #expect(controller.currentArticleListSessionID == sessionID)
        #expect(appState.selectedArticleID == articles[70].id)
        let validReference = try #require(appState.currentArticleListSessionReference)
        let protectedOffset = list.contentOffset.y
        controller.followReaderArticle(
            articles[0].id, direction: .previous,
            in: ArticleListSessionReference(
                id: UUID(), sidebarSelection: validReference.sidebarSelection,
                sidebarArticleFilter: validReference.sidebarArticleFilter
            )
        )
        controller.followReaderArticle(UUID(), direction: .next, in: validReference)
        #expect(abs(list.contentOffset.y - protectedOffset) < 1)
        #expect(requests == 2)
        let beforeBack = try #require(list.layoutAttributesForItem(at: IndexPath(item: 70, section: 0)))
        #expect(abs(beforeBack.frame.maxY - list.bounds.inset(by: list.adjustedContentInset).maxY) < 2)
        let preparedOffset = list.contentOffset.y
        // An appearance followed by disappearance models a cancelled return lifecycle.
        host.beginAppearanceTransition(true, animated: true)
        host.endAppearanceTransition()
        host.beginAppearanceTransition(false, animated: true)
        host.endAppearanceTransition()
        #expect(appState.selectedArticleID == articles[70].id)
        #expect(abs(list.contentOffset.y - preparedOffset) < 1)
        appState.selectArticle(nil)
        navigation.popViewController(animated: false)
        host.view.layoutIfNeeded()
        let target = try #require(list.layoutAttributesForItem(at: IndexPath(item: 70, section: 0)))
        #expect(abs(target.frame.maxY - list.bounds.inset(by: list.adjustedContentInset).maxY) < 2)
        let returnedOffset = list.contentOffset.y
        await settle(host)
        #expect(abs(list.contentOffset.y - returnedOffset) < 1)
        #expect(requests == 2)
        #expect(listDrivenLoads == 0)
        if filter == .unread {
            #expect(controller.screenState.articleListSession.entries.prefix(70).allSatisfy { $0.isRetained })
        }
        // A completed reveal must not fight a subsequent manual list scroll.
        list.setContentOffset(.zero, animated: false)
        controller.readerScrollCoordinator.reconcile()
        #expect(abs(list.contentOffset.y) < 1)
    }

    @Test
    func revealPolicyHandlesClippedAndOversizedRowsWithoutAssumingFixedHeights() {
        let viewport = CGRect(x: 0, y: 100, width: 400, height: 300)
        #expect(ArticleListReaderRevealPolicy.scrollDelta(row: CGRect(x: 0, y: 120, width: 400, height: 100), viewport: viewport, direction: .next) == 0)
        #expect(ArticleListReaderRevealPolicy.scrollDelta(row: CGRect(x: 0, y: 90, width: 400, height: 100), viewport: viewport, direction: .previous) == -10)
        #expect(ArticleListReaderRevealPolicy.scrollDelta(row: CGRect(x: 0, y: 350, width: 400, height: 100), viewport: viewport, direction: .next) == 50)
        let oversized = CGRect(x: 0, y: 80, width: 400, height: 500)
        #expect(ArticleListReaderRevealPolicy.scrollDelta(row: oversized, viewport: viewport, direction: .previous) == -20)
        #expect(ArticleListReaderRevealPolicy.scrollDelta(row: oversized, viewport: viewport, direction: .next) == 180)
    }

    private func settle(_ controller: UIViewController) async {
        for _ in 0..<3 {
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
            controller.navigationController?.view.layoutIfNeeded()
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
        }
    }

    private func findList(in view: UIView) -> UICollectionView? {
        if let list = view as? UICollectionView { return list }
        return view.subviews.lazy.compactMap { findList(in: $0) }.first
    }
}

private struct ReaderFollowListFixture: View {
    let appState: AppState
    let articles: [ArticleListItemDTO]
    let coordinator: ArticleListReaderScrollCoordinator
    let sessionID: UUID
    var controller: ArticlesScreenController?
    var loadNextPageAction: @MainActor @Sendable () async -> Void = {}

    var body: some View {
        // RootView observes the route while constructing its detail column.
        let _ = appState.selectedArticleID
        let _ = appState.articleListScrollPositionID(
            sidebarSelection: appState.selectedSidebarSelection, sidebarArticleFilter: appState.selectedSidebarArticleFilter
        )
        ArticleListContentView(
            sections: ArticlesDaySectionsBuilder.build(from: controller?.screenState.articles ?? articles),
            animationState: ArticleListAnimationState(),
            customRefreshState: .idle,
            canLoadNextPage: controller?.screenState.canLoadNextPage ?? false,
            isLoadingNextPage: controller?.screenState.isLoadingNextPage ?? false,
            readerScrollCoordinator: coordinator,
            listSessionID: sessionID,
            selection: Binding(
                get: { appState.selectedArticleID },
                set: { appState.selectArticle($0) }
            ),
            scrollPositionID: Binding(
                get: {
                    appState.articleListScrollPositionID(
                        sidebarSelection: appState.selectedSidebarSelection, sidebarArticleFilter: appState.selectedSidebarArticleFilter
                    )
                },
                set: {
                    appState.updateArticleListScrollPosition(
                        $0, sidebarSelection: appState.selectedSidebarSelection, sidebarArticleFilter: appState.selectedSidebarArticleFilter
                    )
                }
            ),
            customRefreshPullProgressChanged: { _ in },
            customRefreshReleaseAction: {},
            loadNextPageAction: { await loadNextPageAction() },
            toggleReadStatusAction: { _ in },
            toggleStarredAction: { _ in }
        )
    }
}
