import Foundation

struct FolderSidebarItem: Sendable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let sortOrder: Int

    init(id: UUID, name: String, sortOrder: Int) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
    }

    init(folder: Folder) {
        self.init(
            id: folder.id,
            name: folder.name,
            sortOrder: folder.sortOrder
        )
    }
}

struct SourcesSidebarSnapshotDTO: Sendable {
    let folders: [FolderSidebarItem]
    let feeds: [FeedSidebarItem]
    let unreadSmartCount: Int
    let starredSmartCount: Int
    let starredFeedIDs: Set<UUID>

    init(
        folders: [FolderSidebarItem] = [],
        feeds: [FeedSidebarItem],
        unreadSmartCount: Int,
        starredSmartCount: Int,
        starredFeedIDs: Set<UUID>
    ) {
        self.folders = folders
        self.feeds = feeds
        self.unreadSmartCount = unreadSmartCount
        self.starredSmartCount = starredSmartCount
        self.starredFeedIDs = starredFeedIDs
    }
}
