import Foundation

enum SidebarCountPresentation {
    static func smartCount(
        for filter: SourcesFilter,
        unreadSmartCount: Int,
        starredSmartCount: Int
    ) -> Int? {
        switch filter {
        case .allItems, .unread:
            unreadSmartCount
        case .starred:
            starredSmartCount
        }
    }

    static func feedCount(for feed: FeedSidebarItem, filter: SourcesFilter) -> Int {
        switch filter {
        case .allItems, .unread:
            feed.unreadCount
        case .starred:
            feed.starredCount
        }
    }

    static func folderCount(for group: FolderSidebarGroup, filter: SourcesFilter) -> Int {
        switch filter {
        case .allItems, .unread:
            group.unreadCount
        case .starred:
            group.starredCount
        }
    }
}
