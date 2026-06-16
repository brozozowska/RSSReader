import Foundation

enum SidebarCountPresentation {
    static func smartCount(
        for filter: SidebarArticleFilter,
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

    static func feedCount(for feed: FeedSidebarItem, filter: SidebarArticleFilter) -> Int {
        switch filter {
        case .allItems, .unread:
            feed.unreadCount
        case .starred:
            feed.starredCount
        }
    }

    static func folderCount(for group: FolderSidebarGroup, filter: SidebarArticleFilter) -> Int {
        switch filter {
        case .allItems, .unread:
            group.unreadCount
        case .starred:
            group.starredCount
        }
    }
}
