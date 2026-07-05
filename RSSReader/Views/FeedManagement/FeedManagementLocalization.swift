import Foundation

enum FeedManagementLocalization {
    static let screenTitle = String(
        localized: "feedManagement.screen.title",
        defaultValue: "Manage Feeds",
        comment: "Navigation title for the feed management screen."
    )
    static let summaryTitle = String(
        localized: "feedManagement.summary.title",
        defaultValue: "Feeds and Folders",
        comment: "Summary title on the feed management entry screen."
    )
    static let summaryDescription = String(
        localized: "feedManagement.summary.description",
        defaultValue: "Subscribe to new feeds, create folders, and organize feed storage for easier reading.",
        comment: "Summary description on the feed management entry screen."
    )
    static let addSectionTitle = String(
        localized: "feedManagement.section.add.title",
        defaultValue: "Add",
        comment: "Section title for creating new feeds and folders."
    )
    static let addSectionFooter = String(
        localized: "feedManagement.section.add.footer",
        defaultValue: "Start with a feed address, or create a folder first if you already know how you want to organize feeds.",
        comment: "Section footer for creating new feeds and folders."
    )
    static let addFeedTitle = String(
        localized: "feedManagement.addFeed.title",
        defaultValue: "Add Feed",
        comment: "Action title for adding a feed."
    )
    static let addFeedSubtitle = String(
        localized: "feedManagement.addFeed.subtitle",
        defaultValue: "Find a feed, review its details, and choose which folder will store it.",
        comment: "Action subtitle for adding a feed."
    )
    static let createFolderTitle = String(
        localized: "feedManagement.createFolder.title",
        defaultValue: "Create Folder",
        comment: "Action title for creating a folder."
    )
    static let createFolderSubtitle = String(
        localized: "feedManagement.createFolder.subtitle",
        defaultValue: "Group related feeds under a folder name that is easy to scan.",
        comment: "Action subtitle for creating a folder."
    )
    static let organizeSectionTitle = String(
        localized: "feedManagement.section.organize.title",
        defaultValue: "Organize",
        comment: "Section title for organizing existing feeds."
    )
    static let organizeSectionFooter = String(
        localized: "feedManagement.section.organize.footer",
        defaultValue: "Move saved feeds between folders for easier reading.",
        comment: "Section footer for organizing existing feeds."
    )
    static let moveFeedTitle = String(
        localized: "feedManagement.moveFeed.title",
        defaultValue: "Move Feed",
        comment: "Action title for moving a feed."
    )
    static let moveFeedSubtitle = String(
        localized: "feedManagement.moveFeed.subtitle",
        defaultValue: "Change where an existing feed appears in your feed list.",
        comment: "Action subtitle for moving a feed."
    )
    static let closeScreenAccessibilityLabel = String(
        localized: "feedManagement.screen.close.accessibility",
        defaultValue: "Close Manage Feeds",
        comment: "Accessibility label for closing the feed management screen."
    )
    static let closeDestinationAccessibilityFormat = String(
        localized: "feedManagement.destination.close.accessibility.format",
        defaultValue: "Close %@",
        comment: "Accessibility label for closing a feed management destination. Placeholder is the destination title."
    )
    static func closeDestinationAccessibilityLabel(_ title: String) -> String {
        CommonLocalization.localizedTemplate(closeDestinationAccessibilityFormat, title)
    }
    static let feedURLPrompt = String(
        localized: "feedManagement.addFeed.url.prompt",
        defaultValue: "Feed URL",
        comment: "Prompt for the feed URL text field."
    )
    static let feedURLPlaceholder = String(
        localized: "feedManagement.addFeed.url.placeholder",
        defaultValue: "example.com",
        comment: "Placeholder for the feed URL text field."
    )
    static let feedURLFooter = String(
        localized: "feedManagement.addFeed.url.footer",
        defaultValue: "Use a website address or a direct RSS / Atom feed link.",
        comment: "Footer explaining acceptable feed URL input."
    )
    static let displayNamePrompt = String(
        localized: "feedManagement.addFeed.displayName.prompt",
        defaultValue: "Display Name",
        comment: "Prompt for the feed display name text field."
    )
    static let displayNamePlaceholder = String(
        localized: "feedManagement.addFeed.displayName.placeholder",
        defaultValue: "Feed name",
        comment: "Placeholder for the feed display name text field."
    )
    static let feedPreviewTitle = String(
        localized: "feedManagement.addFeed.preview.title",
        defaultValue: "Feed Preview",
        comment: "Section title for feed preview details."
    )
    static let previewFeedAction = String(
        localized: "feedManagement.addFeed.preview.action",
        defaultValue: "Preview Feed",
        comment: "Primary action title for loading a feed preview."
    )
    static let checkingFeedTitle = String(
        localized: "feedManagement.addFeed.checking.title",
        defaultValue: "Checking Feed...",
        comment: "Loading title while checking a feed."
    )
    static let checkingFeedAccessibilityLabel = String(
        localized: "feedManagement.addFeed.checking.accessibility",
        defaultValue: "Checking feed",
        comment: "Accessibility label for the feed preview loading indicator."
    )
    static let feedTypeLabel = String(
        localized: "feedManagement.addFeed.preview.feedType.label",
        defaultValue: "Feed Type",
        comment: "Label for the feed type row in feed preview."
    )
    static let descriptionLabel = String(
        localized: "feedManagement.addFeed.preview.description.label",
        defaultValue: "Description",
        comment: "Label for the description row in feed preview."
    )
    static let feedAddressLabel = String(
        localized: "feedManagement.addFeed.preview.feedAddress.label",
        defaultValue: "Feed Address",
        comment: "Label for the feed address row in feed preview."
    )
    static let previewFailureFooter = String(
        localized: "feedManagement.addFeed.preview.failure.footer",
        defaultValue: "Try a different website address or a direct RSS / Atom feed link.",
        comment: "Footer shown after a feed preview failure."
    )
    static let createFolderInlineDescription = String(
        localized: "feedManagement.addFeed.createFolder.description",
        defaultValue: "Create a folder now if this feed should live in a new group.",
        comment: "Description above the inline create folder action in add feed flow."
    )
    static let destinationFolderTitle = String(
        localized: "feedManagement.addFeed.destinationFolder.title",
        defaultValue: "Destination Folder",
        comment: "Section title for choosing destination folder while adding a feed."
    )
    static let createNewFolderAction = String(
        localized: "feedManagement.createFolder.new.action",
        defaultValue: "Create New Folder",
        comment: "Action title for creating a new folder from feed management."
    )
    static let ungroupedTitle = String(
        localized: "feedManagement.folder.ungrouped.title",
        defaultValue: "Ungrouped",
        comment: "Folder placement title for feeds outside any folder."
    )
    static let ungroupedSubtitle = String(
        localized: "feedManagement.folder.ungrouped.subtitle",
        defaultValue: "Keep the feed outside any folder.",
        comment: "Folder placement subtitle for keeping a feed ungrouped."
    )
    static let selectedFolderTitle = String(
        localized: "feedManagement.folder.selectedFallback.title",
        defaultValue: "Selected Folder",
        comment: "Fallback folder title when a selected folder cannot be resolved."
    )
    static let rssFeedKindTitle = String(
        localized: "feedManagement.feedKind.rss.title",
        defaultValue: "RSS",
        comment: "Technical feed kind title for RSS feeds."
    )
    static let atomFeedKindTitle = String(
        localized: "feedManagement.feedKind.atom.title",
        defaultValue: "Atom",
        comment: "Technical feed kind title for Atom feeds."
    )
    static let unknownFeedKindTitle = String(
        localized: "feedManagement.feedKind.unknown.title",
        defaultValue: "Unknown",
        comment: "Fallback title for an unknown feed kind."
    )
    static let folderNamePrompt = String(
        localized: "feedManagement.createFolder.name.prompt",
        defaultValue: "Folder Name",
        comment: "Prompt for the folder name text field."
    )
    static let folderNamePlaceholder = String(
        localized: "feedManagement.createFolder.name.placeholder",
        defaultValue: "Examples: News, Tech, Design",
        comment: "Placeholder for the folder name text field."
    )
    static let folderNameFooter = String(
        localized: "feedManagement.createFolder.name.footer",
        defaultValue: "Use a name that helps organize feed storage for easier reading.",
        comment: "Footer explaining folder name input."
    )
    static let existingFoldersTitle = String(
        localized: "feedManagement.createFolder.existingFolders.title",
        defaultValue: "Existing Folders",
        comment: "Section title for existing folders."
    )
    static let selectFeedTitle = String(
        localized: "feedManagement.moveFeed.selectFeed.title",
        defaultValue: "Select Feed",
        comment: "Section title for choosing a feed to move."
    )
    static let currentLocationFormat = String(
        localized: "feedManagement.moveFeed.currentLocation.format",
        defaultValue: "Current location: %@",
        comment: "Label showing a feed's current folder placement. Placeholder is the folder placement title."
    )
    static func currentLocation(_ title: String) -> String {
        CommonLocalization.localizedTemplate(currentLocationFormat, title)
    }
    static let targetFolderTitle = String(
        localized: "feedManagement.moveFeed.targetFolder.title",
        defaultValue: "Target Folder",
        comment: "Section title for choosing target folder in move feed flow."
    )
    static func feedCount(_ count: Int) -> String {
        let template = String(
            localized: "feedManagement.feedCount.count",
            defaultValue: "%lld feeds",
            comment: "Label showing a feed count. Placeholder is the feed count."
        )
        return CommonLocalization.localizedCountTemplate(template, count: count)
    }
    static func existingFeedCount(_ count: Int) -> String {
        let template = String(
            localized: "feedManagement.existingFeedCount.count",
            defaultValue: "%lld existing feeds",
            comment: "Label showing an existing feed count in a folder. Placeholder is the feed count."
        )
        return CommonLocalization.localizedCountTemplate(template, count: count)
    }
    static let enterFeedURLValidation = String(
        localized: "feedManagement.addFeed.validation.emptyURL",
        defaultValue: "Enter a feed URL to continue.",
        comment: "Validation message shown when the feed URL field is empty."
    )
    static let invalidFeedURLValidation = String(
        localized: "feedManagement.addFeed.validation.invalidURL",
        defaultValue: "Enter a valid site or feed URL.",
        comment: "Validation message shown when the feed URL field cannot be normalized."
    )
    static let feedUpdatedTitle = String(
        localized: "feedManagement.addFeed.status.updated.title",
        defaultValue: "Feed updated",
        comment: "Success title after updating a feed."
    )
    static let feedAddedTitle = String(
        localized: "feedManagement.addFeed.status.added.title",
        defaultValue: "Feed added",
        comment: "Success title after adding a feed."
    )
    static let feedUpdatedDetailFormat = String(
        localized: "feedManagement.addFeed.status.updated.detail.format",
        defaultValue: "%1$@ now points to %2$@ in %3$@.",
        comment: "Success detail after updating a feed. Placeholders are feed title, URL, and folder title."
    )
    static let feedAddedDetailFormat = String(
        localized: "feedManagement.addFeed.status.added.detail.format",
        defaultValue: "%1$@ was saved in %2$@.",
        comment: "Success detail after adding a feed. Placeholders are feed title and folder title."
    )
    static func feedUpdatedDetail(title: String, url: String, folderTitle: String) -> String {
        CommonLocalization.localizedTemplate(feedUpdatedDetailFormat, title, url, folderTitle)
    }
    static func feedAddedDetail(title: String, folderTitle: String) -> String {
        CommonLocalization.localizedTemplate(feedAddedDetailFormat, title, folderTitle)
    }
    static let loadingPreviewAction = String(
        localized: "feedManagement.addFeed.action.loadingPreview",
        defaultValue: "Loading Preview...",
        comment: "Primary action title while feed preview is loading."
    )
    static let savingChangesAction = String(
        localized: "feedManagement.addFeed.action.savingChanges",
        defaultValue: "Saving Changes...",
        comment: "Primary action title while feed changes are saving."
    )
    static let addingFeedAction = String(
        localized: "feedManagement.addFeed.action.addingFeed",
        defaultValue: "Adding Feed...",
        comment: "Primary action title while a feed is being added."
    )
    static let changesSavedAction = String(
        localized: "feedManagement.addFeed.action.changesSaved",
        defaultValue: "Changes Saved",
        comment: "Primary action title after feed changes were saved."
    )
    static let feedAddedAction = String(
        localized: "feedManagement.addFeed.action.feedAdded",
        defaultValue: "Feed Added",
        comment: "Primary action title after a feed was added."
    )
    static let saveChangesAction = String(
        localized: "feedManagement.addFeed.action.saveChanges",
        defaultValue: "Save Changes",
        comment: "Primary action title for saving feed changes."
    )
    static let alreadyAddedAction = String(
        localized: "feedManagement.addFeed.action.alreadyAdded",
        defaultValue: "Already Added",
        comment: "Primary action title for a duplicate feed."
    )
    static let renameFeedTitle = String(
        localized: "feedManagement.renameFeed.title",
        defaultValue: "Переименовать ленту",
        comment: "Navigation title for renaming a feed."
    )
    static let feedDetailsTitle = String(
        localized: "feedManagement.addFeed.edit.summary.title",
        defaultValue: "Feed Details",
        comment: "Summary title for editing a feed."
    )
    static let feedDetailsDescription = String(
        localized: "feedManagement.addFeed.edit.summary.description",
        defaultValue: "Change the display name or enter a new feed address.",
        comment: "Summary description for editing a feed."
    )
    static let newFeedTitle = String(
        localized: "feedManagement.addFeed.new.summary.title",
        defaultValue: "New Feed",
        comment: "Summary title for adding a feed."
    )
    static let newFeedDescription = String(
        localized: "feedManagement.addFeed.new.summary.description",
        defaultValue: "Enter a website address, and the app will find the feed if it exists.",
        comment: "Summary description for adding a feed."
    )
    static let editDisplayNameFooter = String(
        localized: "feedManagement.renameFeed.displayName.footer",
        defaultValue: "Задайте имя, которое будет отображаться в списке лент и статей.",
        comment: "Footer for display name while renaming a feed."
    )
    static let addDisplayNameFooter = String(
        localized: "feedManagement.addFeed.displayName.add.footer",
        defaultValue: "Leave the feed title unchanged, or create your own.",
        comment: "Footer for display name while adding a feed."
    )
    static let duplicateFeedNotice = String(
        localized: "feedManagement.addFeed.duplicate.notice",
        defaultValue: "This feed already exists in the library.",
        comment: "Warning shown below feed preview when feed already exists."
    )
    static let duplicateFeedTitle = String(
        localized: "feedManagement.addFeed.duplicate.title",
        defaultValue: "This feed is already in the library",
        comment: "Warning title for duplicate feed."
    )
    static let duplicateFeedDetail = String(
        localized: "feedManagement.addFeed.duplicate.detail",
        defaultValue: "Use the existing feed instead of creating a duplicate.",
        comment: "Warning detail for duplicate feed."
    )
    static let savedEditPlacementDescription = String(
        localized: "feedManagement.addFeed.placement.savedEdit.description",
        defaultValue: "The feed has already been updated. Edit the URL to start another edit flow.",
        comment: "Placement footer after editing a feed."
    )
    static let savedAddPlacementDescription = String(
        localized: "feedManagement.addFeed.placement.savedAdd.description",
        defaultValue: "The feed has already been saved. Edit the URL to start a new add-feed flow.",
        comment: "Placement footer after adding a feed."
    )
    static let editPendingPlacementDescription = String(
        localized: "feedManagement.addFeed.placement.editPending.description",
        defaultValue: "The current folder is preselected. Review the feed before saving changes.",
        comment: "Placement footer before editing a feed."
    )
    static let addPendingPlacementDescription = String(
        localized: "feedManagement.addFeed.placement.addPending.description",
        defaultValue: "Review the feed first, then choose whether it should stay ungrouped or live in a folder.",
        comment: "Placement footer before adding a feed."
    )
    static let noFoldersPlacementDescription = String(
        localized: "feedManagement.addFeed.placement.noFolders.description",
        defaultValue: "No folders are available yet. You can keep the feed ungrouped or create a folder.",
        comment: "Placement footer when no folders exist."
    )
    static let editReadyPlacementDescription = String(
        localized: "feedManagement.addFeed.placement.editReady.description",
        defaultValue: "Choose where this feed should appear after saving.",
        comment: "Placement footer after feed preview while editing."
    )
    static let addReadyPlacementDescription = String(
        localized: "feedManagement.addFeed.placement.addReady.description",
        defaultValue: "Choose where this feed should appear after adding it.",
        comment: "Placement footer after feed preview while adding."
    )
    static let folderUpdatedTitle = String(
        localized: "feedManagement.createFolder.status.updated.title",
        defaultValue: "Folder updated",
        comment: "Success title after updating a folder."
    )
    static let folderCreatedTitle = String(
        localized: "feedManagement.createFolder.status.created.title",
        defaultValue: "Folder created",
        comment: "Success title after creating a folder."
    )
    static let folderRenamedDetailFormat = String(
        localized: "feedManagement.createFolder.status.renamed.detail.format",
        defaultValue: "\"%@\" has been renamed.",
        comment: "Success detail after renaming a folder. Placeholder is folder name."
    )
    static let folderCreatedDetailFormat = String(
        localized: "feedManagement.createFolder.status.created.detail.format",
        defaultValue: "\"%@\" is ready for feeds.",
        comment: "Success detail after creating a folder. Placeholder is folder name."
    )
    static func folderRenamedDetail(_ name: String) -> String {
        CommonLocalization.localizedTemplate(folderRenamedDetailFormat, name)
    }
    static func folderCreatedDetail(_ name: String) -> String {
        CommonLocalization.localizedTemplate(folderCreatedDetailFormat, name)
    }
    static let folderUpdateFailedTitle = String(
        localized: "feedManagement.createFolder.status.updateFailed.title",
        defaultValue: "Folder could not be updated",
        comment: "Failure title after updating a folder fails."
    )
    static let folderCreateFailedTitle = String(
        localized: "feedManagement.createFolder.status.createFailed.title",
        defaultValue: "Folder could not be created",
        comment: "Failure title after creating a folder fails."
    )
    static let folderCreationUnavailableTitle = String(
        localized: "feedManagement.createFolder.unavailable.create.title",
        defaultValue: "Folder creation is unavailable",
        comment: "Failure title when folder creation service is unavailable."
    )
    static let folderCreationUnavailableMessage = String(
        localized: "feedManagement.createFolder.unavailable.create.detail",
        defaultValue: "Folder creation is unavailable in the current app environment.",
        comment: "Failure detail when folder creation service is unavailable in the current app environment."
    )
    static let folderEditingUnavailableTitle = String(
        localized: "feedManagement.createFolder.unavailable.edit.title",
        defaultValue: "Folder editing is unavailable",
        comment: "Failure title when folder editing service is unavailable."
    )
    static let folderEditingUnavailableMessage = String(
        localized: "feedManagement.createFolder.unavailable.edit.detail",
        defaultValue: "Folder editing is unavailable in the current app environment.",
        comment: "Failure detail when folder editing service is unavailable in the current app environment."
    )
    static let existingFoldersLoadFailureMessage = String(
        localized: "feedManagement.createFolder.error.loadExistingFolders",
        defaultValue: "Unable to load existing folders right now. Try again.",
        comment: "Failure message when existing folders cannot be loaded for folder creation."
    )
    static let folderDetailsLoadFailureMessage = String(
        localized: "feedManagement.createFolder.error.loadDetails",
        defaultValue: "Unable to load the folder details right now. Try again.",
        comment: "Failure message when folder details cannot be loaded for editing."
    )
    static let editFolderTitle = String(
        localized: "feedManagement.createFolder.edit.title",
        defaultValue: "Edit Folder",
        comment: "Navigation title for editing a folder."
    )
    static let folderNameSummaryTitle = String(
        localized: "feedManagement.createFolder.edit.summary.title",
        defaultValue: "Folder Name",
        comment: "Summary title for editing a folder."
    )
    static let editFolderDescription = String(
        localized: "feedManagement.createFolder.edit.summary.description",
        defaultValue: "Rename this folder. Feeds inside it stay in the same place.",
        comment: "Summary description for editing a folder."
    )
    static let newFolderSummaryTitle = String(
        localized: "feedManagement.createFolder.new.summary.title",
        defaultValue: "New Folder",
        comment: "Summary title for creating a folder."
    )
    static let newFolderDescription = String(
        localized: "feedManagement.createFolder.new.summary.description",
        defaultValue: "Create a folder for feeds you want to keep together.",
        comment: "Summary description for creating a folder."
    )
    static let noFoldersTitle = String(
        localized: "feedManagement.createFolder.empty.title",
        defaultValue: "No folders yet",
        comment: "Empty title when no folders exist."
    )
    static let noFoldersDescription = String(
        localized: "feedManagement.createFolder.empty.description",
        defaultValue: "Create the first folder, then add or move feeds into it.",
        comment: "Empty description when no folders exist."
    )
    static let savingFolderAction = String(
        localized: "feedManagement.createFolder.action.saving",
        defaultValue: "Saving Folder...",
        comment: "Primary action title while saving folder edits."
    )
    static let creatingFolderAction = String(
        localized: "feedManagement.createFolder.action.creating",
        defaultValue: "Creating Folder...",
        comment: "Primary action title while creating a folder."
    )
    static let saveFolderAction = String(
        localized: "feedManagement.createFolder.action.save",
        defaultValue: "Save Folder",
        comment: "Primary action title for saving folder edits."
    )
    static let folderCreationUnavailableValidation = String(
        localized: "feedManagement.createFolder.validation.unavailable",
        defaultValue: "Folder creation is unavailable right now.",
        comment: "Validation message when folder service is unavailable."
    )
    static let enterFolderNameValidation = String(
        localized: "feedManagement.createFolder.validation.emptyName",
        defaultValue: "Enter a folder name to continue.",
        comment: "Validation message when folder name is empty."
    )
    static let duplicateFolderNameValidation = String(
        localized: "feedManagement.createFolder.validation.duplicateName",
        defaultValue: "A folder with this name already exists.",
        comment: "Validation message when folder name duplicates an existing folder."
    )
    static let firstFolderPlacementDescription = String(
        localized: "feedManagement.createFolder.placement.first.description",
        defaultValue: "This will be the first folder.",
        comment: "Placement description when creating the first folder."
    )
    static let editingFolderPlacementDescriptionFormat = String(
        localized: "feedManagement.createFolder.placement.editing.description.format",
        defaultValue: "\"%@\" keeps its current order.",
        comment: "Placement description when editing a folder. Placeholder is folder name."
    )
    static func existingFolderPlacementDescription(count: Int) -> String {
        let template = String(
            localized: "feedManagement.createFolder.placement.afterExisting.description.count",
            defaultValue: "This folder will be added after %lld existing folders.",
            comment: "Placement description when creating a folder after existing folders. Placeholder is the existing folder count."
        )
        return CommonLocalization.localizedCountTemplate(template, count: count)
    }
    static func editingFolderPlacementDescription(name: String) -> String {
        CommonLocalization.localizedTemplate(editingFolderPlacementDescriptionFormat, name)
    }
    static let feedMovedTitle = String(
        localized: "feedManagement.moveFeed.status.moved.title",
        defaultValue: "Feed moved",
        comment: "Success title after moving a feed."
    )
    static let feedMovedDetailFormat = String(
        localized: "feedManagement.moveFeed.status.moved.detail.format",
        defaultValue: "%1$@ now lives in %2$@.",
        comment: "Success detail after moving a feed. Placeholders are feed title and folder title."
    )
    static func feedMovedDetail(feedTitle: String, folderTitle: String) -> String {
        CommonLocalization.localizedTemplate(feedMovedDetailFormat, feedTitle, folderTitle)
    }
    static let feedMoveFailedTitle = String(
        localized: "feedManagement.moveFeed.status.failed.title",
        defaultValue: "Feed could not be moved",
        comment: "Failure title after moving a feed fails."
    )
    static let feedOrganizationTitle = String(
        localized: "feedManagement.moveFeed.summary.title",
        defaultValue: "Feed Organization",
        comment: "Summary title for move feed flow."
    )
    static let feedOrganizationDescription = String(
        localized: "feedManagement.moveFeed.summary.description",
        defaultValue: "Choose an existing feed and move it to the right folder.",
        comment: "Summary description for move feed flow."
    )
    static let noFeedsTitle = String(
        localized: "feedManagement.moveFeed.empty.title",
        defaultValue: "No existing feeds yet",
        comment: "Empty title when no feeds exist."
    )
    static let noFeedsDescription = String(
        localized: "feedManagement.moveFeed.empty.description",
        defaultValue: "Add a feed first, then return here to move it between folders.",
        comment: "Empty description when no feeds exist."
    )
    static let movingFeedAction = String(
        localized: "feedManagement.moveFeed.action.moving",
        defaultValue: "Moving...",
        comment: "Primary action title while moving a feed."
    )
    static let feedMovesUnavailableMessage = String(
        localized: "feedManagement.moveFeed.error.unavailable",
        defaultValue: "Feed moves are unavailable right now.",
        comment: "Failure message when feed move service is unavailable."
    )
    static let feedMovesEnvironmentUnavailableMessage = String(
        localized: "feedManagement.moveFeed.error.environmentUnavailable",
        defaultValue: "Feed moves are unavailable in the current app environment.",
        comment: "Failure message when feed moves are unavailable in the current app environment."
    )
    static let existingFeedsLoadFailureMessage = String(
        localized: "feedManagement.moveFeed.error.loadExistingFeeds",
        defaultValue: "Unable to load existing feeds right now. Try again.",
        comment: "Failure message when existing feeds cannot be loaded for feed moves."
    )
    static let feedMoveSelectionRequiredMessage = String(
        localized: "feedManagement.moveFeed.error.selectionRequired",
        defaultValue: "Select a feed and a different destination before moving it.",
        comment: "Failure message when move feed command is incomplete."
    )
    static let feedMoveGenericFailure = String(
        localized: "feedManagement.moveFeed.error.generic",
        defaultValue: "Unable to move the feed right now. Try again.",
        comment: "Generic feed move failure message."
    )
}
