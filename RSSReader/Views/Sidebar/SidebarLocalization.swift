import Foundation

enum SidebarLocalization {
    static let settingsAccessibilityLabel = String(
        localized: "sidebar.toolbar.settings.accessibility",
        defaultValue: "Settings",
        comment: "Accessibility label for the settings toolbar button in the sidebar."
    )
    static let title = String(
        localized: "sidebar.title",
        defaultValue: "Feeds",
        comment: "Navigation title for the feeds sidebar."
    )
    static let addFeedAccessibilityLabel = String(
        localized: "sidebar.toolbar.addFeed.accessibility",
        defaultValue: "Add Feed",
        comment: "Accessibility label for the add feed toolbar button."
    )
    static let filterFeedsAccessibilityLabel = String(
        localized: "sidebar.toolbar.filter.accessibility",
        defaultValue: "Filter Feeds",
        comment: "Accessibility label for the feed filter menu."
    )
    static let allItemsFilterTitle = String(
        localized: "sidebar.filter.allItems.title",
        defaultValue: "All Items",
        comment: "Menu item title for showing all feed items."
    )
    static let unreadFilterTitle = String(
        localized: "sidebar.filter.unread.title",
        defaultValue: "Unread",
        comment: "Menu item title for showing unread feed items."
    )
    static let starredFilterTitle = String(
        localized: "sidebar.filter.starred.title",
        defaultValue: "Starred",
        comment: "Menu item title for showing starred feed items."
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
    static let renameFeedActionTitle = String(
        localized: "sidebar.contextMenu.renameFeed.title",
        defaultValue: "Rename...",
        comment: "Context menu action title for renaming a feed."
    )
    static let renameFolderActionTitle = String(
        localized: "sidebar.contextMenu.renameFolder.title",
        defaultValue: "Rename...",
        comment: "Context menu action title for renaming a folder."
    )
    static let unsubscribeActionTitle = String(
        localized: "sidebar.contextMenu.unsubscribe.title",
        defaultValue: "Unsubscribe",
        comment: "Destructive context menu action title for unsubscribing from a feed."
    )
    static let unsubscribeConfirmationTitle = String(
        localized: "sidebar.unsubscribeConfirmation.title",
        defaultValue: "Unsubscribe Feed?",
        comment: "Alert title asking the user to confirm unsubscribing from a feed."
    )
    static let unsubscribeConfirmationActionTitle = String(
        localized: "sidebar.unsubscribeConfirmation.action.title",
        defaultValue: "Unsubscribe",
        comment: "Destructive alert action title for confirming feed unsubscribe."
    )
    static let cancelActionTitle = CommonLocalization.cancelAction
    static func unsubscribeConfirmationMessage(feedTitle: String) -> String {
        let format = String(
            localized: "sidebar.unsubscribeConfirmation.message",
            defaultValue: "Unsubscribe from \"%@\"? Articles from this feed will be removed from this device.",
            comment: "Alert message asking the user to confirm unsubscribing from a feed. The placeholder is the feed title."
        )
        return String(format: format, feedTitle)
    }
    static let deleteActionTitle = String(
        localized: "sidebar.contextMenu.delete.title",
        defaultValue: "Delete",
        comment: "Destructive context menu action title for deleting a folder."
    )
    static let folderDeleteConfirmationTitle = String(
        localized: "sidebar.folderDeleteConfirmation.title",
        defaultValue: "Delete Folder?",
        comment: "Alert title asking the user to confirm deleting a folder."
    )
    static let folderDeleteConfirmationActionTitle = String(
        localized: "sidebar.folderDeleteConfirmation.action.title",
        defaultValue: "Delete Folder",
        comment: "Destructive alert action title for confirming folder deletion."
    )
    static func folderDeleteConfirmationMessage(folderName: String) -> String {
        let format = String(
            localized: "sidebar.folderDeleteConfirmation.message",
            defaultValue: "Delete \"%@\"? Feeds inside this folder will not be deleted. They will move to Ungrouped.",
            comment: "Alert message asking the user to confirm deleting a folder. The placeholder is the folder name."
        )
        return String(format: format, folderName)
    }
    static let loadingTitle = String(
        localized: "sidebar.loading.title",
        defaultValue: "Loading Feeds",
        comment: "Loading state title for the feeds sidebar."
    )
    static let emptyTitle = String(
        localized: "sidebar.empty.title",
        defaultValue: "No Feeds",
        comment: "Empty state title for the feeds sidebar."
    )
    static let emptyDescription = String(
        localized: "sidebar.empty.description",
        defaultValue: "Add a feed to populate the Feeds sidebar.",
        comment: "Empty state description for the feeds sidebar."
    )
    static let loadFailureTitle = String(
        localized: "sidebar.loadFailure.title",
        defaultValue: "Unable to Load Feeds",
        comment: "Failure state title for the feeds sidebar."
    )
    static let unavailablePreviewMessage = String(
        localized: "sidebar.preview.unavailable.message",
        defaultValue: "Feeds are unavailable in the current app environment.",
        comment: "Preview failure message for unavailable feeds."
    )
    static let genericLoadFailureMessage = String(
        localized: "sidebar.loadFailure.genericMessage",
        defaultValue: "Unable to load feeds right now. Try again.",
        comment: "Generic failure message shown when the feeds sidebar cannot load feeds."
    )
}
