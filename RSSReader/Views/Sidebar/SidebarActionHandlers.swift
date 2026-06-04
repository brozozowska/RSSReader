import Foundation

struct SidebarActionHandlers {
    let showSettings: () -> Void
    let showSourceManagement: () -> Void
    let applySourcesFilter: (SourcesFilter) -> Void
    let showFeedOrganizer: (UUID) -> Void
    let showFeedEditor: (UUID) -> Void
    let unsubscribeFeed: (UUID) -> Void
    let showFolder: (String) -> Void
    let showFolderEditor: (String) -> Void
    let deleteFolder: (String) -> Void
}
