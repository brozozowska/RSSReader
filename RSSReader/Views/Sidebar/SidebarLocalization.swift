import Foundation

enum SidebarLocalization {
    static let settingsAccessibilityLabel = String(
        localized: "sidebar.toolbar.settings.accessibility",
        defaultValue: "Settings",
        comment: "Accessibility label for the settings toolbar button in the sidebar."
    )
    static let title = String(
        localized: "sidebar.title",
        defaultValue: "Sources",
        comment: "Navigation title for the sources sidebar."
    )
    static let addSourceAccessibilityLabel = String(
        localized: "sidebar.toolbar.addSource.accessibility",
        defaultValue: "Add Source",
        comment: "Accessibility label for the add source toolbar button."
    )
    static let filterSourcesAccessibilityLabel = String(
        localized: "sidebar.toolbar.filter.accessibility",
        defaultValue: "Filter Sources",
        comment: "Accessibility label for the source filter menu."
    )
    static let allItemsFilterTitle = String(
        localized: "sidebar.filter.allItems.title",
        defaultValue: "All Items",
        comment: "Menu item title for showing all source items."
    )
    static let unreadFilterTitle = String(
        localized: "sidebar.filter.unread.title",
        defaultValue: "Unread",
        comment: "Menu item title for showing unread source items."
    )
    static let starredFilterTitle = String(
        localized: "sidebar.filter.starred.title",
        defaultValue: "Starred",
        comment: "Menu item title for showing starred source items."
    )
    static let smartViewsSectionTitle = String(
        localized: "sidebar.section.smartViews.title",
        defaultValue: "Smart Views",
        comment: "Sidebar section title for smart views."
    )
    static let foldersSectionTitle = String(
        localized: "sidebar.section.folders.title",
        defaultValue: "Folders",
        comment: "Sidebar section title for folders."
    )
    static let ungroupedSectionTitle = String(
        localized: "sidebar.section.ungrouped.title",
        defaultValue: "Ungrouped",
        comment: "Sidebar section title for feeds outside folders."
    )
    static let organizeActionTitle = String(
        localized: "sidebar.contextMenu.organize.title",
        defaultValue: "Organize...",
        comment: "Context menu action title for moving a feed."
    )
    static let editActionTitle = String(
        localized: "sidebar.contextMenu.edit.title",
        defaultValue: "Edit...",
        comment: "Context menu action title for editing a feed or folder."
    )
    static let unsubscribeActionTitle = String(
        localized: "sidebar.contextMenu.unsubscribe.title",
        defaultValue: "Unsubscribe",
        comment: "Destructive context menu action title for unsubscribing from a feed."
    )
    static let deleteActionTitle = String(
        localized: "sidebar.contextMenu.delete.title",
        defaultValue: "Delete",
        comment: "Destructive context menu action title for deleting a folder."
    )
    static let loadingTitle = String(
        localized: "sidebar.loading.title",
        defaultValue: "Loading Sources",
        comment: "Loading state title for the sources sidebar."
    )
    static let emptyTitle = String(
        localized: "sidebar.empty.title",
        defaultValue: "No Sources",
        comment: "Empty state title for the sources sidebar."
    )
    static let emptyDescription = String(
        localized: "sidebar.empty.description",
        defaultValue: "Add a source to populate the Sources sidebar.",
        comment: "Empty state description for the sources sidebar."
    )
    static let loadFailureTitle = String(
        localized: "sidebar.loadFailure.title",
        defaultValue: "Unable to Load Sources",
        comment: "Failure state title for the sources sidebar."
    )
    static let unavailablePreviewMessage = String(
        localized: "sidebar.preview.unavailable.message",
        defaultValue: "Sources are unavailable in the current app environment.",
        comment: "Preview failure message for unavailable sources."
    )
    static let genericLoadFailureMessage = String(
        localized: "sidebar.loadFailure.genericMessage",
        defaultValue: "Unable to load sources right now. Try again.",
        comment: "Generic failure message shown when the sources sidebar cannot load sources."
    )
}
