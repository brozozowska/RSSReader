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

        #expect(formatter.text(for: .syncing) == "Syncing...")
    }

    @Test
    func sidebarSubtitleFormatterReturnsPlaceholderWhenNoRefreshDateIsAvailable() {
        let formatter = SidebarSubtitleFormatter()

        #expect(formatter.text(for: .idle(lastUpdatedAt: nil)) == "Not updated yet")
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
        let formatter = SidebarSubtitleFormatter(now: now, calendar: calendar)

        #expect(formatter.text(for: .idle(lastUpdatedAt: refreshDate)) == "Today at 17:08")
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
        let formatter = SidebarSubtitleFormatter(now: now, calendar: calendar)

        #expect(formatter.text(for: .idle(lastUpdatedAt: refreshDate)) == "Yesterday at 17:08")
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
        let formatter = SidebarSubtitleFormatter(now: now, calendar: calendar)

        #expect(formatter.text(for: .idle(lastUpdatedAt: refreshDate)) == "Sunday, 24 May 2026")
    }

    @Test
    func sidebarToolbarStateMarksSyncingStateAndUsesSyncingSubtitle() {
        let state = SidebarToolbarState(refreshStatus: .syncing)

        #expect(state.subtitle == "Syncing...")
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

        #expect(state.subtitle == "Syncing...")
        #expect(state.isSyncing)
    }

    @Test
    func sourceIconCandidateBuilderParsesHTMLIconLinksInPriorityOrder() throws {
        let baseURL = try #require(URL(string: "https://example.com/"))
        let html = """
        <!doctype html>
        <html>
          <head>
            <link rel="icon" sizes="32x32" href="/favicon-32x32.png">
            <link rel="apple-touch-icon" sizes="180x180" href="/apple-touch-icon.png">
            <link rel="mask-icon" href="/mask.svg">
            <link rel="shortcut icon" href="/favicon.ico">
          </head>
          <body></body>
        </html>
        """

        let candidates = SourceIconCandidateBuilder.htmlIconCandidates(in: html, baseURL: baseURL)
            .map(\.absoluteString)

        #expect(candidates == [
            "https://example.com/apple-touch-icon.png",
            "https://example.com/favicon-32x32.png",
            "https://example.com/favicon.ico"
        ])
    }

    @Test
    func sourceIconCandidateBuilderBuildsCommonIconCandidatesFromOrigin() throws {
        let iconURL = try #require(URL(string: "https://example.com/news/favicon.ico"))

        let candidates = SourceIconCandidateBuilder.commonIconCandidates(for: iconURL)
            .map(\.absoluteString)

        #expect(candidates == [
            "https://example.com/apple-touch-icon.png",
            "https://example.com/apple-touch-icon-precomposed.png",
            "https://example.com/favicon-32x32.png",
            "https://example.com/favicon.png",
            "https://example.com/favicon.ico"
        ])
    }

    @Test
    func sourceIconImagePolicyRejectsWideLogoImages() {
        #expect(SourceIconImagePolicy.isSuitableIconSize(CGSize(width: 180, height: 180)))
        #expect(SourceIconImagePolicy.isSuitableIconSize(CGSize(width: 64, height: 32)))
        #expect(SourceIconImagePolicy.isSuitableIconSize(CGSize(width: 240, height: 40)) == false)
        #expect(SourceIconImagePolicy.isSuitableIconSize(CGSize(width: 0, height: 0)) == false)
    }

    @Test
    func sidebarToolbarStateUsesRuntimeFailureStatusForShellToolbar() {
        let refreshDate = Calendar.current.date(byAdding: .hour, value: -2, to: Date()) ?? Date()
        let state = SidebarToolbarState(
            refreshStatus: .idle(lastUpdatedAt: refreshDate),
            iCloudSyncStatus: .failed("Setup failed.")
        )

        #expect(state.subtitle == "Sync failed")
        #expect(state.isSyncing == false)
    }
}
