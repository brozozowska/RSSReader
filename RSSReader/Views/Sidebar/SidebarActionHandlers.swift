import Foundation

struct SidebarActionHandlers {
    let showSettings: () -> Void
    let showFeedManagement: () -> Void
    let applySidebarArticleFilter: (SidebarArticleFilter) -> Void
    let showFeedOrganizer: (UUID) -> Void
    let showFeedEditor: (UUID) -> Void
    let requestFeedUnsubscribeConfirmation: (UUID, String) -> Void
    let showFolder: (String) -> Void
    let showFolderEditor: (String) -> Void
    let requestFolderDeleteConfirmation: (String) -> Void
}
