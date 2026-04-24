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
    func sidebarSubtitleFormatterFormatsTodayRefreshDate() {
        let formatter = SidebarSubtitleFormatter()
        let calendar = Calendar.current
        let now = Date()
        let refreshDate = calendar.date(
            bySettingHour: 9,
            minute: 41,
            second: 0,
            of: now
        ) ?? now

        let expectedText = "Today at \(refreshDate.formatted(date: .omitted, time: .shortened))"

        #expect(formatter.text(for: .idle(lastUpdatedAt: refreshDate)) == expectedText)
    }

    @Test
    func sidebarSubtitleFormatterFormatsYesterdayRefreshDate() {
        let formatter = SidebarSubtitleFormatter()
        let calendar = Calendar.current
        let now = Date()
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        let refreshDate = calendar.date(
            bySettingHour: 21,
            minute: 15,
            second: 0,
            of: yesterday
        ) ?? yesterday

        let expectedText = "Yesterday at \(refreshDate.formatted(date: .omitted, time: .shortened))"

        #expect(formatter.text(for: .idle(lastUpdatedAt: refreshDate)) == expectedText)
    }

    @Test
    func sidebarSubtitleFormatterFormatsOlderRefreshDateWithAbbreviatedDate() {
        let formatter = SidebarSubtitleFormatter()
        let refreshDate = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? .distantPast

        let expectedText = refreshDate.formatted(date: .abbreviated, time: .shortened)

        #expect(formatter.text(for: .idle(lastUpdatedAt: refreshDate)) == expectedText)
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
}
