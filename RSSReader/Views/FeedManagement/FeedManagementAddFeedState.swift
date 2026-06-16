import Foundation

struct FeedManagementAddFeedState {
    private(set) var urlInput = ""
    private(set) var displayNameInput = ""
    private(set) var isLoadingPreview = false
    private(set) var isCreatingFeed = false
    private(set) var activePreviewRequestURL: String? = nil
    private(set) var activePreviewRequestID: UUID? = nil
    private(set) var preview: FeedManagementFeedPreview? = nil
    private(set) var createdFeed: FeedManagementFeedSummary? = nil
    private(set) var previewStatus: FeedManagementAddFeedStatusPresentation? = nil
    private(set) var availableFolders: [FeedManagementFolderSummary] = []
    private(set) var selectedFolderPlacement: FeedManagementFolderPlacement = .ungrouped
    private(set) var editingFeed: FeedManagementFeedSummary? = nil

    var isEditing: Bool {
        editingFeed != nil
    }

    mutating func updateURLInput(_ value: String) {
        guard value != urlInput else { return }

        urlInput = value
        if isEditing == false {
            displayNameInput = ""
        }
        isLoadingPreview = false
        isCreatingFeed = false
        activePreviewRequestURL = nil
        activePreviewRequestID = nil
        preview = nil
        createdFeed = nil
        previewStatus = nil
    }

    mutating func updateDisplayNameInput(_ value: String) {
        guard value != displayNameInput else { return }

        displayNameInput = value
        if createdFeed != nil {
            createdFeed = nil
        }
    }

    mutating func applyAvailableFolders(_ folders: [FeedManagementFolderSummary]) {
        availableFolders = folders.sorted(by: folderSortComparator)
        if case .folder(let folderID) = selectedFolderPlacement,
           availableFolders.contains(where: { $0.id == folderID }) == false {
            selectedFolderPlacement = .ungrouped
        }
    }

    mutating func applyEditingFeed(_ feed: FeedManagementFeedSummary) {
        editingFeed = feed
        urlInput = feed.url
        displayNameInput = feed.title
        isLoadingPreview = false
        isCreatingFeed = false
        activePreviewRequestURL = nil
        activePreviewRequestID = nil
        preview = nil
        createdFeed = nil
        previewStatus = nil
        if let folderID = feed.folderID,
           availableFolders.contains(where: { $0.id == folderID }) {
            selectedFolderPlacement = .folder(folderID)
        } else {
            selectedFolderPlacement = .ungrouped
        }
    }

    mutating func resetForEntry() {
        urlInput = ""
        displayNameInput = ""
        isLoadingPreview = false
        isCreatingFeed = false
        activePreviewRequestURL = nil
        activePreviewRequestID = nil
        preview = nil
        createdFeed = nil
        previewStatus = nil
        selectedFolderPlacement = .ungrouped
        editingFeed = nil
    }

    mutating func selectFolderPlacement(_ placement: FeedManagementFolderPlacement) {
        guard isCreatingFeed == false, createdFeed == nil else { return }

        switch placement {
        case .ungrouped:
            selectedFolderPlacement = .ungrouped
        case .folder(let folderID):
            guard availableFolders.contains(where: { $0.id == folderID }) else { return }
            selectedFolderPlacement = .folder(folderID)
        }
    }

    func validationMessage() -> String? {
        let normalizedInput = normalizedURLInput()
        guard normalizedInput.isEmpty == false else {
            return FeedManagementLocalization.enterFeedURLValidation
        }

        guard (try? FeedManagementFeedDiscoveryPlanner.makePlan(for: normalizedInput)) != nil else {
            return FeedManagementLocalization.invalidFeedURLValidation
        }

        return nil
    }

    func canCreateFeed() -> Bool {
        preview != nil
            && editingFeed == nil
            && hasDuplicateConflict == false
            && isLoadingPreview == false
            && isCreatingFeed == false
            && createdFeed == nil
    }

    func canUpdateFeed() -> Bool {
        (preview != nil || canUpdateDisplayNameWithoutPreview())
            && editingFeed != nil
            && hasDuplicateConflict == false
            && isLoadingPreview == false
            && isCreatingFeed == false
            && createdFeed == nil
    }

    func shouldPreviewBeforeSaving() -> Bool {
        guard let editingFeed else { return false }
        guard let normalizedURL = normalizedValidatedURL() else { return false }
        guard normalizedURL != editingFeed.url else { return false }

        if let preview {
            return preview.requestedURL != normalizedURL
                && preview.resolvedFeedURL != normalizedURL
        }

        return true
    }

    mutating func beginPreviewLoading() -> FeedManagementAddFeedPreviewCommand? {
        guard isLoadingPreview == false,
              isCreatingFeed == false,
              let normalizedURL = normalizedValidatedURL() else {
            return nil
        }

        let requestID = UUID()
        isLoadingPreview = true
        isCreatingFeed = false
        activePreviewRequestURL = normalizedURL
        activePreviewRequestID = requestID
        preview = nil
        createdFeed = nil
        previewStatus = nil
        return FeedManagementAddFeedPreviewCommand(
            requestID: requestID,
            urlString: normalizedURL
        )
    }

    mutating func applyLoadedPreview(
        _ preview: FeedManagementFeedPreview,
        command: FeedManagementAddFeedPreviewCommand
    ) {
        guard activePreviewRequestID == command.requestID,
              activePreviewRequestURL == command.urlString else {
            return
        }

        self.preview = preview
        if isEditing == false {
            displayNameInput = preview.title
        }
        isLoadingPreview = false
        isCreatingFeed = false
        activePreviewRequestURL = nil
        activePreviewRequestID = nil
        previewStatus = nil
        createdFeed = nil
    }

    mutating func applyPreviewFailure(
        status: FeedManagementAddFeedStatusPresentation,
        command: FeedManagementAddFeedPreviewCommand?
    ) {
        if let command {
            guard activePreviewRequestID == command.requestID,
                  activePreviewRequestURL == command.urlString else {
                return
            }
        }

        isLoadingPreview = false
        isCreatingFeed = false
        activePreviewRequestURL = nil
        activePreviewRequestID = nil
        preview = nil
        createdFeed = nil
        previewStatus = status
    }

    mutating func beginFeedCreation() -> FeedManagementCreateFeedCommand? {
        guard canCreateFeed(), let preview else { return nil }

        isCreatingFeed = true
        previewStatus = nil

        return FeedManagementCreateFeedCommand(
            preview: preview,
            displayTitleOverride: displayTitleOverride(metadataTitle: preview.title),
            folderPlacement: selectedFolderPlacement
        )
    }

    mutating func beginFeedUpdate() -> FeedManagementUpdateFeedCommand? {
        guard canUpdateFeed(), let editingFeed else { return nil }

        isCreatingFeed = true
        previewStatus = nil

        return FeedManagementUpdateFeedCommand(
            feedID: editingFeed.id,
            preview: preview,
            displayTitleOverride: displayTitleOverride(
                metadataTitle: preview?.title ?? editingFeed.metadataTitle
            ),
            folderPlacement: selectedFolderPlacement
        )
    }

    mutating func applyCreatedFeed(_ feed: FeedManagementFeedSummary) {
        let wasEditing = isEditing
        createdFeed = feed
        isCreatingFeed = false
        editingFeed = wasEditing ? feed : nil
        previewStatus = FeedManagementAddFeedStatusPresentation(
            title: wasEditing
                ? FeedManagementLocalization.feedUpdatedTitle
                : FeedManagementLocalization.feedAddedTitle,
            kind: .success,
            detail: wasEditing
                ? FeedManagementLocalization.feedUpdatedDetail(
                    title: feed.title,
                    url: feed.url,
                    folderTitle: feed.folderName ?? FeedManagementLocalization.ungroupedTitle
                )
                : FeedManagementLocalization.feedAddedDetail(
                    title: feed.title,
                    folderTitle: feed.folderName ?? FeedManagementLocalization.ungroupedTitle
                )
        )
    }

    mutating func applyFeedCreationFailure(
        status: FeedManagementAddFeedStatusPresentation
    ) {
        isCreatingFeed = false
        createdFeed = nil
        previewStatus = status
    }

    func derivedPresentation() -> FeedManagementAddFeedPresentation {
        let validationMessage = validationMessage()
        let normalizedURL = normalizedValidatedURL()
        let primaryActionTitle: String
        let isPrimaryActionEnabled: Bool

        if isLoadingPreview {
            primaryActionTitle = FeedManagementLocalization.loadingPreviewAction
            isPrimaryActionEnabled = false
        } else if isCreatingFeed {
            primaryActionTitle = isEditing
                ? FeedManagementLocalization.savingChangesAction
                : FeedManagementLocalization.addingFeedAction
            isPrimaryActionEnabled = false
        } else if createdFeed != nil {
            primaryActionTitle = isEditing
                ? FeedManagementLocalization.changesSavedAction
                : FeedManagementLocalization.feedAddedAction
            isPrimaryActionEnabled = false
        } else if previewStatus?.kind == .failure {
            primaryActionTitle = FeedManagementLocalization.previewFeedAction
            isPrimaryActionEnabled = false
        } else if canUpdateDisplayNameWithoutPreview() {
            primaryActionTitle = FeedManagementLocalization.saveChangesAction
            isPrimaryActionEnabled = true
        } else if preview != nil {
            if hasDuplicateConflict {
                primaryActionTitle = FeedManagementLocalization.alreadyAddedAction
                isPrimaryActionEnabled = false
            } else {
                primaryActionTitle = isEditing
                    ? FeedManagementLocalization.saveChangesAction
                    : FeedManagementLocalization.addFeedTitle
                isPrimaryActionEnabled = true
            }
        } else {
            primaryActionTitle = FeedManagementLocalization.previewFeedAction
            isPrimaryActionEnabled = validationMessage == nil
        }
        let isConfirmationActionEnabled = (preview != nil || canUpdateDisplayNameWithoutPreview())
            && hasDuplicateConflict == false
            && isLoadingPreview == false
            && isCreatingFeed == false
            && createdFeed == nil

        return FeedManagementAddFeedPresentation(
            title: isEditing
                ? FeedManagementLocalization.editFeedTitle
                : FeedManagementLocalization.addFeedTitle,
            summaryTitle: isEditing
                ? FeedManagementLocalization.feedDetailsTitle
                : FeedManagementLocalization.newFeedTitle,
            summaryDescription: isEditing
                ? FeedManagementLocalization.feedDetailsDescription
                : FeedManagementLocalization.newFeedDescription,
            urlInput: urlInput,
            urlPrompt: FeedManagementLocalization.feedURLPrompt,
            displayNameInput: displayNameInput,
            displayNamePrompt: FeedManagementLocalization.displayNamePrompt,
            displayNameFooter: displayNameFooter(),
            showsDisplayNameInput: showsDisplayNameInput(),
            validationMessage: validationMessage,
            normalizedURL: normalizedURL,
            primaryActionTitle: primaryActionTitle,
            isPrimaryActionEnabled: isPrimaryActionEnabled,
            isConfirmationActionEnabled: isConfirmationActionEnabled,
            isLoadingPreview: isLoadingPreview,
            preview: previewPresentation(),
            placementTitle: FeedManagementLocalization.destinationFolderTitle,
            placementDescription: placementDescription(),
            placementOptions: placementOptions(),
            createFolderActionTitle: createFolderActionTitle(),
            status: statusPresentation()
        )
    }

    private var hasDuplicateConflict: Bool {
        guard let existingFeedID = preview?.existingFeedID else { return false }
        return existingFeedID != editingFeed?.id
    }

    private func normalizedURLInput() -> String {
        urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedDisplayNameInput() -> String {
        displayNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedValidatedURL() -> String? {
        guard validationMessage() == nil else { return nil }
        return FeedManagementFeedDiscoveryPlanner.displayURLString(for: normalizedURLInput())
    }

    private func displayTitleOverride(metadataTitle: String) -> String? {
        let displayName = normalizedDisplayNameInput()
        guard displayName.isEmpty == false,
              displayName != metadataTitle else {
            return nil
        }
        return displayName
    }

    private func displayNameFooter() -> String {
        if isEditing {
            return FeedManagementLocalization.editDisplayNameFooter
        }
        return FeedManagementLocalization.addDisplayNameFooter
    }

    private func canUpdateDisplayNameWithoutPreview() -> Bool {
        guard let editingFeed else { return false }
        guard preview == nil else { return false }
        guard normalizedValidatedURL() == editingFeed.url else { return false }
        return normalizedDisplayNameInput() != editingFeed.title
    }

    private func previewPresentation() -> FeedManagementAddFeedPreviewPresentation? {
        guard let preview else { return nil }

        return FeedManagementAddFeedPreviewPresentation(
            title: preview.title,
            subtitle: preview.subtitle,
            siteURL: preview.siteURL,
            iconURL: preview.iconURL,
            kindTitle: kindTitle(preview.kind),
            resolvedFeedURL: preview.resolvedFeedURL,
            existingFeedNotice: hasDuplicateConflict
                ? FeedManagementLocalization.duplicateFeedNotice
                : nil,
            diagnosticsSummary: nil
        )
    }

    private func showsDisplayNameInput() -> Bool {
        guard createdFeed == nil else { return false }
        return preview != nil || isEditing
    }

    private func statusPresentation() -> FeedManagementAddFeedStatusPresentation? {
        if let previewStatus {
            return previewStatus
        }

        if hasDuplicateConflict {
            return FeedManagementAddFeedStatusPresentation(
                title: FeedManagementLocalization.duplicateFeedTitle,
                kind: .warning,
                detail: FeedManagementLocalization.duplicateFeedDetail
            )
        }

        return nil
    }

    private func placementDescription() -> String {
        if createdFeed != nil {
            return isEditing
                ? FeedManagementLocalization.savedEditPlacementDescription
                : FeedManagementLocalization.savedAddPlacementDescription
        }

        if preview == nil {
            if isEditing {
                return FeedManagementLocalization.editPendingPlacementDescription
            }
            return FeedManagementLocalization.addPendingPlacementDescription
        }

        if availableFolders.isEmpty {
            return FeedManagementLocalization.noFoldersPlacementDescription
        }

        return isEditing
            ? FeedManagementLocalization.editReadyPlacementDescription
            : FeedManagementLocalization.addReadyPlacementDescription
    }

    private func placementOptions() -> [FeedManagementFolderPlacementOptionPresentation] {
        guard createdFeed == nil,
              isCreatingFeed == false,
              hasDuplicateConflict == false,
              isEditing == false,
              preview != nil || isEditing else { return [] }

        return [
            FeedManagementFolderPlacementOptionPresentation(
                placement: .ungrouped,
                title: FeedManagementLocalization.ungroupedTitle,
                subtitle: FeedManagementLocalization.ungroupedSubtitle,
                trailingValue: nil,
                isSelected: selectedFolderPlacement == .ungrouped
            )
        ] + availableFolders.map { folder in
            FeedManagementFolderPlacementOptionPresentation(
                placement: .folder(folder.id),
                title: folder.name,
                subtitle: FeedManagementLocalization.existingFeedCount(folder.feedCount),
                trailingValue: nil,
                isSelected: selectedFolderPlacement == .folder(folder.id)
            )
        }
    }

    private func createFolderActionTitle() -> String? {
        guard createdFeed == nil,
              isCreatingFeed == false,
              hasDuplicateConflict == false,
              isEditing == false,
              preview != nil || isEditing else {
            return nil
        }
        return FeedManagementLocalization.createNewFolderAction
    }

    private func selectedPlacementTitle() -> String {
        switch selectedFolderPlacement {
        case .ungrouped:
            return FeedManagementLocalization.ungroupedTitle
        case .folder(let folderID):
            return availableFolders.first(where: { $0.id == folderID })?.name
                ?? FeedManagementLocalization.selectedFolderTitle
        }
    }

    private func kindTitle(_ kind: FeedKind) -> String {
        switch kind {
        case .rss:
            return FeedManagementLocalization.rssFeedKindTitle
        case .atom:
            return FeedManagementLocalization.atomFeedKindTitle
        case .unknown:
            return FeedManagementLocalization.unknownFeedKindTitle
        }
    }

    private func folderSortComparator(
        lhs: FeedManagementFolderSummary,
        rhs: FeedManagementFolderSummary
    ) -> Bool {
        if lhs.sortOrder == rhs.sortOrder {
            if lhs.name == rhs.name {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.name < rhs.name
        }
        return lhs.sortOrder < rhs.sortOrder
    }
}
