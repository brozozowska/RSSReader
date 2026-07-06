import Foundation
import Testing
@testable import RSSReader

@Suite("Sidebar / Presentation")
@MainActor
struct SidebarPresentationTests {
    @Test
    func sidebarCountPresentationUsesUnreadCountersForAllItemsAndUnreadFilters() {
        let feed = FeedSidebarItem(
            feed: Feed(id: UUID(), url: "https://example.com/feed.xml", title: "Feed"),
            unreadCount: 3,
            starredCount: 2
        )
        let folder = FolderSidebarGroup(name: "Tech", feeds: [feed])

        #expect(
            SidebarCountPresentation.smartCount(
                for: .allItems,
                unreadSmartCount: 5,
                starredSmartCount: 2
            ) == 5
        )
        #expect(
            SidebarCountPresentation.smartCount(
                for: .unread,
                unreadSmartCount: 5,
                starredSmartCount: 2
            ) == 5
        )
        #expect(SidebarCountPresentation.feedCount(for: feed, filter: .allItems) == 3)
        #expect(SidebarCountPresentation.feedCount(for: feed, filter: .unread) == 3)
        #expect(SidebarCountPresentation.folderCount(for: folder, filter: .allItems) == 3)
        #expect(SidebarCountPresentation.folderCount(for: folder, filter: .unread) == 3)
    }

    @Test
    func sidebarCountPresentationUsesStarredCountersForStarredFilter() {
        let firstFeed = FeedSidebarItem(
            feed: Feed(id: UUID(), url: "https://example.com/feed-one.xml", title: "Feed One"),
            unreadCount: 4,
            starredCount: 1
        )
        let secondFeed = FeedSidebarItem(
            feed: Feed(id: UUID(), url: "https://example.com/feed-two.xml", title: "Feed Two"),
            unreadCount: 2,
            starredCount: 3
        )
        let folder = FolderSidebarGroup(name: "Tech", feeds: [firstFeed, secondFeed])

        #expect(
            SidebarCountPresentation.smartCount(
                for: .starred,
                unreadSmartCount: 6,
                starredSmartCount: 4
            ) == 4
        )
        #expect(SidebarCountPresentation.feedCount(for: firstFeed, filter: .starred) == 1)
        #expect(SidebarCountPresentation.feedCount(for: secondFeed, filter: .starred) == 3)
        #expect(SidebarCountPresentation.folderCount(for: folder, filter: .starred) == 4)
    }

    @Test
    func sidebarSubtitleFormatterReturnsSyncingTitleForSyncingState() {
        let formatter = SidebarSubtitleFormatter()

        #expect(formatter.text(for: .syncing) == RuntimeFeedbackLocalization.syncingStatusTitle)
    }

    @Test
    func sidebarSubtitleFormatterReturnsPlaceholderWhenNoRefreshDateIsAvailable() {
        let formatter = SidebarSubtitleFormatter()

        #expect(formatter.text(for: .idle(lastUpdatedAt: nil)) == RuntimeFeedbackLocalization.notUpdatedYetStatusTitle)
    }

    @Test
    func sidebarSubtitleFormatterFormatsTodayRefreshDate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let now = try #require(calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026,
            month: 5,
            day: 24,
            hour: 18,
            minute: 30
        )))
        let refreshDate = try #require(calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026,
            month: 5,
            day: 24,
            hour: 17,
            minute: 8
        )))
        let formatter = SidebarSubtitleFormatter(
            now: now,
            calendar: calendar,
            locale: Locale(identifier: "en_GB")
        )

        #expect(formatter.text(for: .idle(lastUpdatedAt: refreshDate)) == RuntimeFeedbackLocalization.todayRefreshStatus(time: "17:08"))
    }

    @Test
    func sidebarSubtitleFormatterFormatsYesterdayRefreshDate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let now = try #require(calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026,
            month: 5,
            day: 25,
            hour: 9,
            minute: 0
        )))
        let refreshDate = try #require(calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026,
            month: 5,
            day: 24,
            hour: 17,
            minute: 8
        )))
        let formatter = SidebarSubtitleFormatter(
            now: now,
            calendar: calendar,
            locale: Locale(identifier: "en_GB")
        )

        #expect(formatter.text(for: .idle(lastUpdatedAt: refreshDate)) == RuntimeFeedbackLocalization.yesterdayRefreshStatus(time: "17:08"))
    }

    @Test
    func sidebarSubtitleFormatterFormatsOlderRefreshDateWithFullDate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let now = try #require(calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026,
            month: 5,
            day: 26,
            hour: 9,
            minute: 0
        )))
        let refreshDate = try #require(calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026,
            month: 5,
            day: 24,
            hour: 17,
            minute: 8
        )))
        let formatter = SidebarSubtitleFormatter(
            now: now,
            calendar: calendar,
            locale: Locale(identifier: "en_GB")
        )

        #expect(
            formatter.text(for: .idle(lastUpdatedAt: refreshDate))
                == refreshDate.formatted(
                    .dateTime
                        .locale(Locale(identifier: "en_GB"))
                        .weekday(.wide)
                        .day()
                        .month(.wide)
                        .year()
                )
        )
    }

    @Test
    func sidebarToolbarStateMarksSyncingStateAndUsesSyncingSubtitle() {
        let state = SidebarToolbarState(refreshStatus: .syncing)

        #expect(state.subtitle == RuntimeFeedbackLocalization.syncingStatusTitle)
        #expect(state.isSyncing)
    }

    @Test
    func sidebarToolbarStateMarksIdleStateAndUsesFormattedSubtitle() {
        let refreshDate = Calendar.current.date(byAdding: .hour, value: -2, to: Date()) ?? Date()
        let formatter = SidebarSubtitleFormatter()
        let expectedSubtitle = formatter.text(for: .idle(lastUpdatedAt: refreshDate))
        let state = SidebarToolbarState(refreshStatus: .idle(lastUpdatedAt: refreshDate))

        #expect(state.subtitle == expectedSubtitle)
        #expect(state.isSyncing == false)
    }

    @Test
    func sidebarToolbarStateUsesRuntimeSyncingStatusForShellToolbar() {
        let refreshDate = Calendar.current.date(byAdding: .hour, value: -2, to: Date()) ?? Date()
        let state = SidebarToolbarState(
            refreshStatus: .idle(lastUpdatedAt: refreshDate),
            iCloudSyncStatus: .syncing
        )

        #expect(state.subtitle == RuntimeFeedbackLocalization.syncingStatusTitle)
        #expect(state.isSyncing)
    }

    @Test
    func sidebarCustomRefreshStateMapsPullProgressToIndicatorContract() {
        let idleState = SidebarCustomRefreshState.pulling(progress: -0.1)
        let pullingState = SidebarCustomRefreshState.pulling(progress: 0.4)
        let readyState = SidebarCustomRefreshState.pulling(progress: 1.2)
        let refreshingState = SidebarCustomRefreshState.refreshing

        #expect(idleState == .idle)
        #expect(idleState.showsIndicator == false)
        #expect(idleState.indicatorState == .idle)

        #expect(pullingState.phase == .pulling)
        #expect(pullingState.pullProgress == 0.4)
        #expect(pullingState.indicatorState == .pulling(progress: 0.4))

        #expect(readyState.phase == .ready)
        #expect(readyState.pullProgress == 1)
        #expect(readyState.indicatorState == .ready)

        #expect(refreshingState.phase == .refreshing)
        #expect(refreshingState.indicatorState == .refreshing)
    }

    @Test
    func sidebarCustomRefreshPoliciesMapOverscrollAndReleaseToRefresh() {
        let partialPullGeometry = SidebarCustomRefreshGeometry(
            contentOffsetY: -48,
            contentInsetTop: 12
        )
        let readyPullGeometry = SidebarCustomRefreshGeometry(
            contentOffsetY: -120,
            contentInsetTop: 12
        )

        #expect(
            SidebarCustomRefreshPullPolicy.progress(
                for: partialPullGeometry,
                threshold: 72
            ) == 0.5
        )
        #expect(
            SidebarCustomRefreshPullPolicy.progress(
                for: readyPullGeometry,
                threshold: 72
            ) == 1
        )
        #expect(
            SidebarCustomRefreshReleasePolicy.shouldTriggerRefresh(
                wasInteracting: true,
                isInteracting: false,
                customRefreshState: .pulling(progress: 1)
            )
        )
        #expect(
            SidebarCustomRefreshReleasePolicy.shouldTriggerRefresh(
                wasInteracting: true,
                isInteracting: false,
                customRefreshState: .pulling(progress: 0.5)
            ) == false
        )
    }

    @Test
    func sidebarToolbarStateUsesRuntimeFailureStatusForShellToolbar() {
        let refreshDate = Calendar.current.date(byAdding: .hour, value: -2, to: Date()) ?? Date()
        let state = SidebarToolbarState(
            refreshStatus: .idle(lastUpdatedAt: refreshDate),
            iCloudSyncStatus: .failed("Setup failed.")
        )

        #expect(state.subtitle == RuntimeFeedbackLocalization.syncFailedStatusTitle)
        #expect(state.isSyncing == false)
    }
}
