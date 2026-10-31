import Foundation

enum AppContentReloadTrigger: Equatable, Sendable {
    case remoteSyncImport
    case backgroundRefresh
}

/// Tokens are invalidation signals; one content event updates the correlated set.
struct AppReloadState {
    private(set) var articleListReloadID = UUID()
    private(set) var sidebarReloadID = UUID()
    private(set) var feedIconCacheResetID = UUID()
    private(set) var articleScreenReloadID = UUID()
    private(set) var lastContentReloadTrigger: AppContentReloadTrigger?

    mutating func requestArticleListReload() { articleListReloadID = UUID() }
    mutating func requestSidebarReload() { sidebarReloadID = UUID() }
    mutating func requestFeedIconCacheReset() { feedIconCacheResetID = UUID() }
    mutating func requestArticleScreenReload() { articleScreenReloadID = UUID() }

    mutating func requestContentReload(_ trigger: AppContentReloadTrigger) {
        lastContentReloadTrigger = trigger
        requestSidebarReload()
        requestArticleListReload()
        requestArticleScreenReload()
    }
}
