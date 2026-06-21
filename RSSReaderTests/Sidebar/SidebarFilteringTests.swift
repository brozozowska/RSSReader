import Foundation
import Testing
@testable import RSSReader

@Suite("Sidebar / Filtering")
@MainActor
struct SidebarFilteringTests {
    @Test
    func sidebarArticleFilterArticleListFilterResolverMapsSidebarArticleFilterToExpectedArticleFilter() {
        #expect(SidebarArticleFilterResolver.resolve(for: .allItems) == .all)
        #expect(SidebarArticleFilterResolver.resolve(for: .unread) == .unread)
        #expect(SidebarArticleFilterResolver.resolve(for: .starred) == .starred)
    }

    @Test
    func sidebarSmartViewsShowOnlyActiveFilterRow() {
        #expect(SmartSidebarItem.visibleItems(for: .allItems, hasFeeds: true) == [.allItems])
        #expect(SmartSidebarItem.visibleItems(for: .unread, hasFeeds: true) == [.unread])
        #expect(SmartSidebarItem.visibleItems(for: .starred, hasFeeds: true) == [.starred])
    }

    @Test
    func sidebarSmartViewsAreHiddenWhenThereAreNoFeeds() {
        #expect(SmartSidebarItem.visibleItems(for: .allItems, hasFeeds: false).isEmpty)
        #expect(SmartSidebarItem.visibleItems(for: .unread, hasFeeds: false).isEmpty)
        #expect(SmartSidebarItem.visibleItems(for: .starred, hasFeeds: false).isEmpty)
    }

    @Test
    func sidebarShowsOnlyFeedsWithStarredArticlesWhenStarredFilterIsActive() {
        let feedOneID = UUID()
        let feedTwoID = UUID()
        let newsFolder = Folder(name: "News")
        let feeds = [
            FeedSidebarItem(
                feed: Feed(id: feedOneID, url: "https://example.com/feed-one.xml", title: "Feed One", folder: newsFolder),
                unreadCount: 2
            ),
            FeedSidebarItem(
                feed: Feed(id: feedTwoID, url: "https://example.com/feed-two.xml", title: "Feed Two"),
                unreadCount: 0
            )
        ]

        let filteredFeeds = SidebarFeedVisibility.filteredFeeds(
            feeds: feeds,
            filter: .starred,
            starredFeedIDs: [feedTwoID]
        )

        #expect(filteredFeeds.map(\.id) == [feedTwoID])
    }

    @Test
    func sidebarKeepsAllFeedsVisibleForAllItemsFilter() {
        let feedOneID = UUID()
        let feedTwoID = UUID()
        let newsFolder = Folder(name: "News")
        let feeds = [
            FeedSidebarItem(
                feed: Feed(id: feedOneID, url: "https://example.com/feed-one.xml", title: "Feed One", folder: newsFolder),
                unreadCount: 2
            ),
            FeedSidebarItem(
                feed: Feed(id: feedTwoID, url: "https://example.com/feed-two.xml", title: "Feed Two"),
                unreadCount: 0
            )
        ]

        let allItemsFeeds = SidebarFeedVisibility.filteredFeeds(
            feeds: feeds,
            filter: .allItems,
            starredFeedIDs: [feedTwoID]
        )

        #expect(allItemsFeeds.map(\.id) == feeds.map(\.id))
        #expect(allItemsFeeds.map(\.unreadCount) == feeds.map(\.unreadCount))
    }

    @Test
    func sidebarShowsOnlyFeedsWithUnreadArticlesWhenUnreadFilterIsActive() {
        let feedOneID = UUID()
        let feedTwoID = UUID()
        let newsFolder = Folder(name: "News")
        let feeds = [
            FeedSidebarItem(
                feed: Feed(id: feedOneID, url: "https://example.com/feed-one.xml", title: "Feed One", folder: newsFolder),
                unreadCount: 2
            ),
            FeedSidebarItem(
                feed: Feed(id: feedTwoID, url: "https://example.com/feed-two.xml", title: "Feed Two"),
                unreadCount: 0
            )
        ]

        let filteredFeeds = SidebarFeedVisibility.filteredFeeds(
            feeds: feeds,
            filter: .unread,
            starredFeedIDs: []
        )

        #expect(filteredFeeds.map(\.id) == [feedOneID])
    }

    @Test
    func sidebarHidesFoldersSectionWhenFilteredFeedsDoNotContainFolders() {
        let ungroupedFeed = FeedSidebarItem(
            feed: Feed(id: UUID(), url: "https://example.com/feed.xml", title: "Ungrouped Feed"),
            unreadCount: 1
        )

        let groups = FolderSidebarGroup.groups(from: [ungroupedFeed])

        #expect(groups.isEmpty)
    }

    @Test
    func sidebarKeepsEmptyFoldersForAllItemsFilter() {
        let emptyFolderID = UUID()
        let groups = FolderSidebarGroup.groups(
            from: [
                FolderSidebarItem(
                    id: emptyFolderID,
                    name: "Empty",
                    sortOrder: 0
                )
            ],
            feeds: [],
            filter: .allItems
        )

        #expect(groups.map(\.folderID) == [emptyFolderID])
        #expect(groups.map(\.name) == ["Empty"])
        #expect(groups.first?.feeds.isEmpty == true)
    }

    @Test
    func sidebarHidesEmptyFoldersForUnreadAndStarredFilters() {
        let folders = [
            FolderSidebarItem(
                id: UUID(),
                name: "Empty",
                sortOrder: 0
            )
        ]

        #expect(FolderSidebarGroup.groups(from: folders, feeds: [], filter: .unread).isEmpty)
        #expect(FolderSidebarGroup.groups(from: folders, feeds: [], filter: .starred).isEmpty)
    }

    @Test
    func sidebarHidesUngroupedSectionWhenFilteredFeedsDoNotContainUngroupedFeeds() {
        let folder = Folder(name: "News")
        let groupedFeed = FeedSidebarItem(
            feed: Feed(id: UUID(), url: "https://example.com/feed.xml", title: "Grouped Feed", folder: folder),
            unreadCount: 1
        )

        let ungroupedFeeds = SidebarUngroupedFeeds.visibleFeeds(from: [groupedFeed])

        #expect(ungroupedFeeds.isEmpty)
    }
}
