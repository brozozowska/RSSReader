import Foundation

struct SourcesSidebarSnapshotDTO: Sendable {
    let feeds: [FeedSidebarItem]
    let unreadSmartCount: Int
    let starredSmartCount: Int
    let starredFeedIDs: Set<UUID>
}
