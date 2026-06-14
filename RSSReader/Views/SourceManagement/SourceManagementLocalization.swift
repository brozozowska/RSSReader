import Foundation

enum SourceManagementLocalization {
    static let screenTitle = String(
        localized: "sourceManagement.screen.title",
        defaultValue: "Add Source",
        comment: "Navigation title for the source management screen."
    )
    static let summaryTitle = String(
        localized: "sourceManagement.summary.title",
        defaultValue: "Manage sources and folders",
        comment: "Summary title on the source management entry screen."
    )
    static let summaryDescription = String(
        localized: "sourceManagement.summary.description",
        defaultValue: "Add new feeds, create folders, or move existing sources when your reading list needs a different structure.",
        comment: "Summary description on the source management entry screen."
    )
    static let addSectionTitle = String(
        localized: "sourceManagement.section.add.title",
        defaultValue: "Add",
        comment: "Section title for creating new sources and folders."
    )
    static let addSectionFooter = String(
        localized: "sourceManagement.section.add.footer",
        defaultValue: "Start with a feed address, or create a folder first if you already know how you want to organize sources.",
        comment: "Section footer for creating new sources and folders."
    )
    static let addFeedTitle = String(
        localized: "sourceManagement.addFeed.title",
        defaultValue: "Add Feed",
        comment: "Action title for adding a feed."
    )
    static let addFeedSubtitle = String(
        localized: "sourceManagement.addFeed.subtitle",
        defaultValue: "Find a feed, review its details, and choose where it belongs.",
        comment: "Action subtitle for adding a feed."
    )
    static let newFeedBadge = String(
        localized: "sourceManagement.addFeed.badge",
        defaultValue: "New Feed",
        comment: "Badge title for the add feed action."
    )
    static let createFolderTitle = String(
        localized: "sourceManagement.createFolder.title",
        defaultValue: "Create Folder",
        comment: "Action title for creating a folder."
    )
    static let createFolderSubtitle = String(
        localized: "sourceManagement.createFolder.subtitle",
        defaultValue: "Group related sources under a folder name that is easy to scan.",
        comment: "Action subtitle for creating a folder."
    )
    static let newFolderBadge = String(
        localized: "sourceManagement.createFolder.badge",
        defaultValue: "New Folder",
        comment: "Badge title for the create folder action."
    )
    static let organizeSectionTitle = String(
        localized: "sourceManagement.section.organize.title",
        defaultValue: "Organize",
        comment: "Section title for organizing existing sources."
    )
    static let organizeSectionFooter = String(
        localized: "sourceManagement.section.organize.footer",
        defaultValue: "Move saved feeds between folders without adding them again.",
        comment: "Section footer for organizing existing sources."
    )
    static let moveSourceTitle = String(
        localized: "sourceManagement.moveSource.title",
        defaultValue: "Move Source",
        comment: "Action title for moving a source."
    )
    static let moveSourceSubtitle = String(
        localized: "sourceManagement.moveSource.subtitle",
        defaultValue: "Change where an existing feed appears in your source list.",
        comment: "Action subtitle for moving a source."
    )
    static let existingSourcesBadge = String(
        localized: "sourceManagement.moveSource.badge",
        defaultValue: "Existing Sources",
        comment: "Badge title for moving an existing source."
    )
    static let closeScreenAccessibilityLabel = String(
        localized: "sourceManagement.screen.close.accessibility",
        defaultValue: "Close Add Source",
        comment: "Accessibility label for closing the source management screen."
    )
    static let closeDestinationAccessibilityFormat = String(
        localized: "sourceManagement.destination.close.accessibility.format",
        defaultValue: "Close %@",
        comment: "Accessibility label for closing a source management destination. Placeholder is the destination title."
    )
    static func closeDestinationAccessibilityLabel(_ title: String) -> String {
        String.localizedStringWithFormat(closeDestinationAccessibilityFormat, title)
    }

    static let feedURLPrompt = String(
        localized: "sourceManagement.addFeed.url.prompt",
        defaultValue: "Feed URL",
        comment: "Prompt for the feed URL text field."
    )
    static let feedURLPlaceholder = String(
        localized: "sourceManagement.addFeed.url.placeholder",
        defaultValue: "example.com",
        comment: "Placeholder for the feed URL text field."
    )
    static let feedURLFooter = String(
        localized: "sourceManagement.addFeed.url.footer",
        defaultValue: "Use a website address or a direct RSS / Atom feed link.",
        comment: "Footer explaining acceptable feed URL input."
    )
    static let displayNamePrompt = String(
        localized: "sourceManagement.addFeed.displayName.prompt",
        defaultValue: "Display Name",
        comment: "Prompt for the source display name text field."
    )
    static let displayNamePlaceholder = String(
        localized: "sourceManagement.addFeed.displayName.placeholder",
        defaultValue: "Source name",
        comment: "Placeholder for the source display name text field."
    )
    static let sourcePreviewTitle = String(
        localized: "sourceManagement.addFeed.preview.title",
        defaultValue: "Source Preview",
        comment: "Section title for feed preview details."
    )
    static let previewFeedAction = String(
        localized: "sourceManagement.addFeed.preview.action",
        defaultValue: "Preview Feed",
        comment: "Primary action title for loading a feed preview."
    )
    static let checkingSourceTitle = String(
        localized: "sourceManagement.addFeed.checking.title",
        defaultValue: "Checking Source...",
        comment: "Loading title while checking a feed source."
    )
    static let checkingSourceAccessibilityLabel = String(
        localized: "sourceManagement.addFeed.checking.accessibility",
        defaultValue: "Checking source",
        comment: "Accessibility label for the feed preview loading indicator."
    )
    static let feedTypeLabel = String(
        localized: "sourceManagement.addFeed.preview.feedType.label",
        defaultValue: "Feed Type",
        comment: "Label for the feed type row in feed preview."
    )
    static let descriptionLabel = String(
        localized: "sourceManagement.addFeed.preview.description.label",
        defaultValue: "Description",
        comment: "Label for the description row in feed preview."
    )
    static let feedAddressLabel = String(
        localized: "sourceManagement.addFeed.preview.feedAddress.label",
        defaultValue: "Feed Address",
        comment: "Label for the feed address row in feed preview."
    )
    static let previewFailureFooter = String(
        localized: "sourceManagement.addFeed.preview.failure.footer",
        defaultValue: "Try a different website address or a direct RSS / Atom feed link.",
        comment: "Footer shown after a feed preview failure."
    )
    static let createFolderInlineDescription = String(
        localized: "sourceManagement.addFeed.createFolder.description",
        defaultValue: "Create a folder now if this source should live in a new group.",
        comment: "Description above the inline create folder action in add feed flow."
    )
    static let destinationFolderTitle = String(
        localized: "sourceManagement.addFeed.destinationFolder.title",
        defaultValue: "Destination Folder",
        comment: "Section title for choosing destination folder while adding a feed."
    )
    static let createNewFolderAction = String(
        localized: "sourceManagement.createFolder.new.action",
        defaultValue: "Create New Folder",
        comment: "Action title for creating a new folder from source management."
    )
    static let ungroupedTitle = String(
        localized: "sourceManagement.folder.ungrouped.title",
        defaultValue: "Ungrouped",
        comment: "Folder placement title for sources outside any folder."
    )
    static let ungroupedSubtitle = String(
        localized: "sourceManagement.folder.ungrouped.subtitle",
        defaultValue: "Keep the source outside any folder.",
        comment: "Folder placement subtitle for keeping a source ungrouped."
    )
    static let selectedFolderTitle = String(
        localized: "sourceManagement.folder.selectedFallback.title",
        defaultValue: "Selected Folder",
        comment: "Fallback folder title when a selected folder cannot be resolved."
    )
    static let unknownFeedKindTitle = String(
        localized: "sourceManagement.feedKind.unknown.title",
        defaultValue: "Unknown",
        comment: "Fallback title for an unknown feed kind."
    )

    static let folderNamePrompt = String(
        localized: "sourceManagement.createFolder.name.prompt",
        defaultValue: "Folder Name",
        comment: "Prompt for the folder name text field."
    )
    static let folderNamePlaceholder = String(
        localized: "sourceManagement.createFolder.name.placeholder",
        defaultValue: "Examples: News, Tech, Design",
        comment: "Placeholder for the folder name text field."
    )
    static let folderNameFooter = String(
        localized: "sourceManagement.createFolder.name.footer",
        defaultValue: "Use a name that is easy to recognize in the source list.",
        comment: "Footer explaining folder name input."
    )
    static let existingFoldersTitle = String(
        localized: "sourceManagement.createFolder.existingFolders.title",
        defaultValue: "Existing Folders",
        comment: "Section title for existing folders."
    )
    static let selectSourceTitle = String(
        localized: "sourceManagement.moveSource.selectSource.title",
        defaultValue: "Select Source",
        comment: "Section title for choosing a source to move."
    )
    static let currentLocationFormat = String(
        localized: "sourceManagement.moveSource.currentLocation.format",
        defaultValue: "Current location: %@",
        comment: "Label showing a source's current folder placement. Placeholder is the folder placement title."
    )
    static func currentLocation(_ title: String) -> String {
        String.localizedStringWithFormat(currentLocationFormat, title)
    }
    static let targetFolderTitle = String(
        localized: "sourceManagement.moveSource.targetFolder.title",
        defaultValue: "Target Folder",
        comment: "Section title for choosing target folder in move source flow."
    )
    static func feedCount(_ count: Int) -> String {
        let format = String(
            localized: "sourceManagement.feedCount.format",
            defaultValue: "%lld feeds",
            comment: "Label showing a feed count. The value is the number of feeds."
        )
        let one = String(
            localized: "sourceManagement.feedCount.one",
            defaultValue: "1 feed",
            comment: "Label for exactly one feed."
        )
        return count == 1 ? one : String.localizedStringWithFormat(format, count)
    }
    static func existingFeedCount(_ count: Int) -> String {
        let format = String(
            localized: "sourceManagement.existingFeedCount.format",
            defaultValue: "%lld existing feeds",
            comment: "Label showing an existing feed count for a folder. The value is the number of feeds."
        )
        let one = String(
            localized: "sourceManagement.existingFeedCount.one",
            defaultValue: "1 existing feed",
            comment: "Label for exactly one existing feed in a folder."
        )
        return count == 1 ? one : String.localizedStringWithFormat(format, count)
    }

    static let enterFeedURLValidation = String(
        localized: "sourceManagement.addFeed.validation.emptyURL",
        defaultValue: "Enter a feed URL to continue.",
        comment: "Validation message shown when the feed URL field is empty."
    )
    static let invalidFeedURLValidation = String(
        localized: "sourceManagement.addFeed.validation.invalidURL",
        defaultValue: "Enter a valid site or feed URL.",
        comment: "Validation message shown when the feed URL field cannot be normalized."
    )
    static let feedUpdatedTitle = String(localized: "sourceManagement.addFeed.status.updated.title", defaultValue: "Feed updated", comment: "Success title after updating a feed.")
    static let feedAddedTitle = String(localized: "sourceManagement.addFeed.status.added.title", defaultValue: "Feed added", comment: "Success title after adding a feed.")
    static let feedUpdatedDetailFormat = String(localized: "sourceManagement.addFeed.status.updated.detail.format", defaultValue: "%1$@ now points to %2$@ in %3$@.", comment: "Success detail after updating a feed. Placeholders are feed title, URL, and folder title.")
    static let feedAddedDetailFormat = String(localized: "sourceManagement.addFeed.status.added.detail.format", defaultValue: "%1$@ was saved in %2$@.", comment: "Success detail after adding a feed. Placeholders are feed title and folder title.")
    static func feedUpdatedDetail(title: String, url: String, folderTitle: String) -> String {
        String.localizedStringWithFormat(feedUpdatedDetailFormat, title, url, folderTitle)
    }
    static func feedAddedDetail(title: String, folderTitle: String) -> String {
        String.localizedStringWithFormat(feedAddedDetailFormat, title, folderTitle)
    }

    static let loadingPreviewAction = String(localized: "sourceManagement.addFeed.action.loadingPreview", defaultValue: "Loading Preview...", comment: "Primary action title while feed preview is loading.")
    static let savingChangesAction = String(localized: "sourceManagement.addFeed.action.savingChanges", defaultValue: "Saving Changes...", comment: "Primary action title while feed changes are saving.")
    static let addingFeedAction = String(localized: "sourceManagement.addFeed.action.addingFeed", defaultValue: "Adding Feed...", comment: "Primary action title while a feed is being added.")
    static let changesSavedAction = String(localized: "sourceManagement.addFeed.action.changesSaved", defaultValue: "Changes Saved", comment: "Primary action title after feed changes were saved.")
    static let feedAddedAction = String(localized: "sourceManagement.addFeed.action.feedAdded", defaultValue: "Feed Added", comment: "Primary action title after a feed was added.")
    static let saveChangesAction = String(localized: "sourceManagement.addFeed.action.saveChanges", defaultValue: "Save Changes", comment: "Primary action title for saving feed changes.")
    static let alreadyAddedAction = String(localized: "sourceManagement.addFeed.action.alreadyAdded", defaultValue: "Already Added", comment: "Primary action title for a duplicate feed.")

    static let editFeedTitle = String(localized: "sourceManagement.addFeed.edit.title", defaultValue: "Edit Feed", comment: "Navigation title for editing a feed.")
    static let sourceDetailsTitle = String(localized: "sourceManagement.addFeed.edit.summary.title", defaultValue: "Source Details", comment: "Summary title for editing a feed.")
    static let sourceDetailsDescription = String(localized: "sourceManagement.addFeed.edit.summary.description", defaultValue: "Change the display name, or preview a new feed address when the source has moved.", comment: "Summary description for editing a feed.")
    static let newSourceTitle = String(localized: "sourceManagement.addFeed.new.summary.title", defaultValue: "New Source", comment: "Summary title for adding a feed.")
    static let newSourceDescription = String(localized: "sourceManagement.addFeed.new.summary.description", defaultValue: "Enter a website or feed address. The app will look for a readable feed before you add it.", comment: "Summary description for adding a feed.")
    static let editDisplayNameFooter = String(localized: "sourceManagement.addFeed.displayName.edit.footer", defaultValue: "Set the name shown for this source in Sources and article lists.", comment: "Footer for display name while editing a feed.")
    static let addDisplayNameFooter = String(localized: "sourceManagement.addFeed.displayName.add.footer", defaultValue: "Leave the feed title unchanged, or choose a custom name for this source.", comment: "Footer for display name while adding a feed.")
    static let duplicateSourceNotice = String(localized: "sourceManagement.addFeed.duplicate.notice", defaultValue: "This source already exists in the library.", comment: "Warning shown below feed preview when feed already exists.")
    static let duplicateFeedTitle = String(localized: "sourceManagement.addFeed.duplicate.title", defaultValue: "This feed is already in the library", comment: "Warning title for duplicate feed.")
    static let duplicateFeedDetail = String(localized: "sourceManagement.addFeed.duplicate.detail", defaultValue: "Use the existing source instead of creating a duplicate subscription.", comment: "Warning detail for duplicate feed.")
    static let savedEditPlacementDescription = String(localized: "sourceManagement.addFeed.placement.savedEdit.description", defaultValue: "The source has already been updated. Edit the URL to start another edit flow.", comment: "Placement footer after editing a feed.")
    static let savedAddPlacementDescription = String(localized: "sourceManagement.addFeed.placement.savedAdd.description", defaultValue: "The source has already been saved. Edit the URL to start a new add-feed flow.", comment: "Placement footer after adding a feed.")
    static let editPendingPlacementDescription = String(localized: "sourceManagement.addFeed.placement.editPending.description", defaultValue: "The current folder is preselected. Review the source before saving changes.", comment: "Placement footer before editing a feed.")
    static let addPendingPlacementDescription = String(localized: "sourceManagement.addFeed.placement.addPending.description", defaultValue: "Review the source first, then choose whether it should stay ungrouped or live in a folder.", comment: "Placement footer before adding a feed.")
    static let noFoldersPlacementDescription = String(localized: "sourceManagement.addFeed.placement.noFolders.description", defaultValue: "No folders are available yet. You can keep the source ungrouped or create a folder.", comment: "Placement footer when no folders exist.")
    static let editReadyPlacementDescription = String(localized: "sourceManagement.addFeed.placement.editReady.description", defaultValue: "Choose where this source should appear after saving.", comment: "Placement footer after feed preview while editing.")
    static let addReadyPlacementDescription = String(localized: "sourceManagement.addFeed.placement.addReady.description", defaultValue: "Choose where this source should appear after adding it.", comment: "Placement footer after feed preview while adding.")

    static let folderUpdatedTitle = String(localized: "sourceManagement.createFolder.status.updated.title", defaultValue: "Folder updated", comment: "Success title after updating a folder.")
    static let folderCreatedTitle = String(localized: "sourceManagement.createFolder.status.created.title", defaultValue: "Folder created", comment: "Success title after creating a folder.")
    static let folderRenamedDetailFormat = String(localized: "sourceManagement.createFolder.status.renamed.detail.format", defaultValue: "\"%@\" has been renamed.", comment: "Success detail after renaming a folder. Placeholder is folder name.")
    static let folderCreatedDetailFormat = String(localized: "sourceManagement.createFolder.status.created.detail.format", defaultValue: "\"%@\" is ready for sources.", comment: "Success detail after creating a folder. Placeholder is folder name.")
    static func folderRenamedDetail(_ name: String) -> String { String.localizedStringWithFormat(folderRenamedDetailFormat, name) }
    static func folderCreatedDetail(_ name: String) -> String { String.localizedStringWithFormat(folderCreatedDetailFormat, name) }
    static let folderUpdateFailedTitle = String(localized: "sourceManagement.createFolder.status.updateFailed.title", defaultValue: "Folder could not be updated", comment: "Failure title after updating a folder fails.")
    static let folderCreateFailedTitle = String(localized: "sourceManagement.createFolder.status.createFailed.title", defaultValue: "Folder could not be created", comment: "Failure title after creating a folder fails.")
    static let editFolderTitle = String(localized: "sourceManagement.createFolder.edit.title", defaultValue: "Edit Folder", comment: "Navigation title for editing a folder.")
    static let folderNameSummaryTitle = String(localized: "sourceManagement.createFolder.edit.summary.title", defaultValue: "Folder Name", comment: "Summary title for editing a folder.")
    static let editFolderDescription = String(localized: "sourceManagement.createFolder.edit.summary.description", defaultValue: "Rename this folder. Sources inside it stay in the same place.", comment: "Summary description for editing a folder.")
    static let newFolderSummaryTitle = String(localized: "sourceManagement.createFolder.new.summary.title", defaultValue: "New Folder", comment: "Summary title for creating a folder.")
    static let newFolderDescription = String(localized: "sourceManagement.createFolder.new.summary.description", defaultValue: "Create a folder for sources you want to keep together.", comment: "Summary description for creating a folder.")
    static let noFoldersTitle = String(localized: "sourceManagement.createFolder.empty.title", defaultValue: "No folders yet", comment: "Empty title when no folders exist.")
    static let noFoldersDescription = String(localized: "sourceManagement.createFolder.empty.description", defaultValue: "Create the first folder, then add or move sources into it.", comment: "Empty description when no folders exist.")
    static let savingFolderAction = String(localized: "sourceManagement.createFolder.action.saving", defaultValue: "Saving Folder...", comment: "Primary action title while saving folder edits.")
    static let creatingFolderAction = String(localized: "sourceManagement.createFolder.action.creating", defaultValue: "Creating Folder...", comment: "Primary action title while creating a folder.")
    static let saveFolderAction = String(localized: "sourceManagement.createFolder.action.save", defaultValue: "Save Folder", comment: "Primary action title for saving folder edits.")
    static let folderCreationUnavailableValidation = String(localized: "sourceManagement.createFolder.validation.unavailable", defaultValue: "Folder creation is unavailable right now.", comment: "Validation message when folder service is unavailable.")
    static let enterFolderNameValidation = String(localized: "sourceManagement.createFolder.validation.emptyName", defaultValue: "Enter a folder name to continue.", comment: "Validation message when folder name is empty.")
    static let duplicateFolderNameValidation = String(localized: "sourceManagement.createFolder.validation.duplicateName", defaultValue: "A folder with this name already exists.", comment: "Validation message when folder name duplicates an existing folder.")
    static let firstFolderPlacementDescription = String(localized: "sourceManagement.createFolder.placement.first.description", defaultValue: "This will be the first folder.", comment: "Placement description when creating the first folder.")
    static let existingFolderPlacementDescriptionFormat = String(localized: "sourceManagement.createFolder.placement.afterExisting.description.format", defaultValue: "This folder will be added after %lld existing folders.", comment: "Placement description when creating a folder after existing folders. Placeholder is folder count.")
    static let editingFolderPlacementDescriptionFormat = String(localized: "sourceManagement.createFolder.placement.editing.description.format", defaultValue: "\"%@\" keeps its current order.", comment: "Placement description when editing a folder. Placeholder is folder name.")
    static func existingFolderPlacementDescription(count: Int) -> String { String.localizedStringWithFormat(existingFolderPlacementDescriptionFormat, count) }
    static func editingFolderPlacementDescription(name: String) -> String { String.localizedStringWithFormat(editingFolderPlacementDescriptionFormat, name) }

    static let sourceMovedTitle = String(localized: "sourceManagement.moveSource.status.moved.title", defaultValue: "Source moved", comment: "Success title after moving a source.")
    static let sourceMovedDetailFormat = String(localized: "sourceManagement.moveSource.status.moved.detail.format", defaultValue: "%1$@ now lives in %2$@.", comment: "Success detail after moving a source. Placeholders are feed title and folder title.")
    static func sourceMovedDetail(feedTitle: String, folderTitle: String) -> String { String.localizedStringWithFormat(sourceMovedDetailFormat, feedTitle, folderTitle) }
    static let sourceMoveFailedTitle = String(localized: "sourceManagement.moveSource.status.failed.title", defaultValue: "Source could not be moved", comment: "Failure title after moving a source fails.")
    static let sourceOrganizationTitle = String(localized: "sourceManagement.moveSource.summary.title", defaultValue: "Source Organization", comment: "Summary title for move source flow.")
    static let sourceOrganizationDescription = String(localized: "sourceManagement.moveSource.summary.description", defaultValue: "Choose a saved feed and move it to the folder where it belongs.", comment: "Summary description for move source flow.")
    static let noFeedsTitle = String(localized: "sourceManagement.moveSource.empty.title", defaultValue: "No existing feeds yet", comment: "Empty title when no feeds exist.")
    static let noFeedsDescription = String(localized: "sourceManagement.moveSource.empty.description", defaultValue: "Add a source first, then return here to move it between folders.", comment: "Empty description when no feeds exist.")
    static let movingSourceAction = String(localized: "sourceManagement.moveSource.action.moving", defaultValue: "Moving...", comment: "Primary action title while moving a source.")
    static let sourceMovesUnavailableMessage = String(localized: "sourceManagement.moveSource.error.unavailable", defaultValue: "Source moves are unavailable right now.", comment: "Failure message when source move service is unavailable.")
    static let sourceMoveSelectionRequiredMessage = String(localized: "sourceManagement.moveSource.error.selectionRequired", defaultValue: "Select a source and a different destination before moving it.", comment: "Failure message when move source command is incomplete.")
    static let sourceMoveGenericFailure = String(localized: "sourceManagement.moveSource.error.generic", defaultValue: "Unable to move the source right now. Try again.", comment: "Generic source move failure message.")
}
