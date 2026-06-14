import Foundation

struct SourceManagementAddFeedState {
    private(set) var urlInput = ""
    private(set) var displayNameInput = ""
    private(set) var isLoadingPreview = false
    private(set) var isCreatingFeed = false
    private(set) var activePreviewRequestURL: String? = nil
    private(set) var activePreviewRequestID: UUID? = nil
    private(set) var preview: SourceManagementFeedPreview? = nil
    private(set) var createdFeed: SourceManagementFeedSummary? = nil
    private(set) var previewStatus: SourceManagementAddFeedStatusPresentation? = nil
    private(set) var availableFolders: [SourceManagementFolderSummary] = []
    private(set) var selectedFolderPlacement: SourceManagementFolderPlacement = .ungrouped
    private(set) var editingFeed: SourceManagementFeedSummary? = nil

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

    mutating func applyAvailableFolders(_ folders: [SourceManagementFolderSummary]) {
        availableFolders = folders.sorted(by: folderSortComparator)
        if case .folder(let folderID) = selectedFolderPlacement,
           availableFolders.contains(where: { $0.id == folderID }) == false {
            selectedFolderPlacement = .ungrouped
        }
    }

    mutating func applyEditingFeed(_ feed: SourceManagementFeedSummary) {
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

    mutating func selectFolderPlacement(_ placement: SourceManagementFolderPlacement) {
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
            return SourceManagementLocalization.enterFeedURLValidation
        }

        guard (try? SourceManagementFeedDiscoveryPlanner.makePlan(for: normalizedInput)) != nil else {
            return SourceManagementLocalization.invalidFeedURLValidation
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

    mutating func beginPreviewLoading() -> SourceManagementAddFeedPreviewCommand? {
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
        return SourceManagementAddFeedPreviewCommand(
            requestID: requestID,
            urlString: normalizedURL
        )
    }

    mutating func applyLoadedPreview(
        _ preview: SourceManagementFeedPreview,
        command: SourceManagementAddFeedPreviewCommand
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
        status: SourceManagementAddFeedStatusPresentation,
        command: SourceManagementAddFeedPreviewCommand?
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

    mutating func beginFeedCreation() -> SourceManagementCreateFeedCommand? {
        guard canCreateFeed(), let preview else { return nil }

        isCreatingFeed = true
        previewStatus = nil

        return SourceManagementCreateFeedCommand(
            preview: preview,
            displayTitleOverride: displayTitleOverride(metadataTitle: preview.title),
            folderPlacement: selectedFolderPlacement
        )
    }

    mutating func beginFeedUpdate() -> SourceManagementUpdateFeedCommand? {
        guard canUpdateFeed(), let editingFeed else { return nil }

        isCreatingFeed = true
        previewStatus = nil

        return SourceManagementUpdateFeedCommand(
            feedID: editingFeed.id,
            preview: preview,
            displayTitleOverride: displayTitleOverride(
                metadataTitle: preview?.title ?? editingFeed.metadataTitle
            ),
            folderPlacement: selectedFolderPlacement
        )
    }

    mutating func applyCreatedFeed(_ feed: SourceManagementFeedSummary) {
        let wasEditing = isEditing
        createdFeed = feed
        isCreatingFeed = false
        editingFeed = wasEditing ? feed : nil
        previewStatus = SourceManagementAddFeedStatusPresentation(
            title: wasEditing
                ? SourceManagementLocalization.feedUpdatedTitle
                : SourceManagementLocalization.feedAddedTitle,
            kind: .success,
            detail: wasEditing
                ? SourceManagementLocalization.feedUpdatedDetail(
                    title: feed.title,
                    url: feed.url,
                    folderTitle: feed.folderName ?? SourceManagementLocalization.ungroupedTitle
                )
                : SourceManagementLocalization.feedAddedDetail(
                    title: feed.title,
                    folderTitle: feed.folderName ?? SourceManagementLocalization.ungroupedTitle
                )
        )
    }

    mutating func applyFeedCreationFailure(
        status: SourceManagementAddFeedStatusPresentation
    ) {
        isCreatingFeed = false
        createdFeed = nil
        previewStatus = status
    }

    func derivedPresentation() -> SourceManagementAddFeedPresentation {
        let validationMessage = validationMessage()
        let normalizedURL = normalizedValidatedURL()
        let primaryActionTitle: String
        let isPrimaryActionEnabled: Bool

        if isLoadingPreview {
            primaryActionTitle = SourceManagementLocalization.loadingPreviewAction
            isPrimaryActionEnabled = false
        } else if isCreatingFeed {
            primaryActionTitle = isEditing
                ? SourceManagementLocalization.savingChangesAction
                : SourceManagementLocalization.addingFeedAction
            isPrimaryActionEnabled = false
        } else if createdFeed != nil {
            primaryActionTitle = isEditing
                ? SourceManagementLocalization.changesSavedAction
                : SourceManagementLocalization.feedAddedAction
            isPrimaryActionEnabled = false
        } else if previewStatus?.kind == .failure {
            primaryActionTitle = SourceManagementLocalization.previewFeedAction
            isPrimaryActionEnabled = false
        } else if canUpdateDisplayNameWithoutPreview() {
            primaryActionTitle = SourceManagementLocalization.saveChangesAction
            isPrimaryActionEnabled = true
        } else if preview != nil {
            if hasDuplicateConflict {
                primaryActionTitle = SourceManagementLocalization.alreadyAddedAction
                isPrimaryActionEnabled = false
            } else {
                primaryActionTitle = isEditing
                    ? SourceManagementLocalization.saveChangesAction
                    : SourceManagementLocalization.addFeedTitle
                isPrimaryActionEnabled = true
            }
        } else {
            primaryActionTitle = SourceManagementLocalization.previewFeedAction
            isPrimaryActionEnabled = validationMessage == nil
        }
        let isConfirmationActionEnabled = (preview != nil || canUpdateDisplayNameWithoutPreview())
            && hasDuplicateConflict == false
            && isLoadingPreview == false
            && isCreatingFeed == false
            && createdFeed == nil

        return SourceManagementAddFeedPresentation(
            title: isEditing
                ? SourceManagementLocalization.editFeedTitle
                : SourceManagementLocalization.addFeedTitle,
            summaryTitle: isEditing
                ? SourceManagementLocalization.sourceDetailsTitle
                : SourceManagementLocalization.newSourceTitle,
            summaryDescription: isEditing
                ? SourceManagementLocalization.sourceDetailsDescription
                : SourceManagementLocalization.newSourceDescription,
            urlInput: urlInput,
            urlPrompt: SourceManagementLocalization.feedURLPrompt,
            displayNameInput: displayNameInput,
            displayNamePrompt: SourceManagementLocalization.displayNamePrompt,
            displayNameFooter: displayNameFooter(),
            showsDisplayNameInput: showsDisplayNameInput(),
            validationMessage: validationMessage,
            normalizedURL: normalizedURL,
            primaryActionTitle: primaryActionTitle,
            isPrimaryActionEnabled: isPrimaryActionEnabled,
            isConfirmationActionEnabled: isConfirmationActionEnabled,
            isLoadingPreview: isLoadingPreview,
            preview: previewPresentation(),
            placementTitle: SourceManagementLocalization.destinationFolderTitle,
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
        return SourceManagementFeedDiscoveryPlanner.displayURLString(for: normalizedURLInput())
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
            return SourceManagementLocalization.editDisplayNameFooter
        }
        return SourceManagementLocalization.addDisplayNameFooter
    }

    private func canUpdateDisplayNameWithoutPreview() -> Bool {
        guard let editingFeed else { return false }
        guard preview == nil else { return false }
        guard normalizedValidatedURL() == editingFeed.url else { return false }
        return normalizedDisplayNameInput() != editingFeed.title
    }

    private func previewPresentation() -> SourceManagementAddFeedPreviewPresentation? {
        guard let preview else { return nil }

        return SourceManagementAddFeedPreviewPresentation(
            title: preview.title,
            subtitle: preview.subtitle,
            siteURL: preview.siteURL,
            iconURL: preview.iconURL,
            kindTitle: kindTitle(preview.kind),
            resolvedFeedURL: preview.resolvedFeedURL,
            existingFeedNotice: hasDuplicateConflict
                ? SourceManagementLocalization.duplicateSourceNotice
                : nil,
            diagnosticsSummary: nil
        )
    }

    private func showsDisplayNameInput() -> Bool {
        guard createdFeed == nil else { return false }
        return preview != nil || isEditing
    }

    private func statusPresentation() -> SourceManagementAddFeedStatusPresentation? {
        if let previewStatus {
            return previewStatus
        }

        if hasDuplicateConflict {
            return SourceManagementAddFeedStatusPresentation(
                title: SourceManagementLocalization.duplicateFeedTitle,
                kind: .warning,
                detail: SourceManagementLocalization.duplicateFeedDetail
            )
        }

        return nil
    }

    private func placementDescription() -> String {
        if createdFeed != nil {
            return isEditing
                ? SourceManagementLocalization.savedEditPlacementDescription
                : SourceManagementLocalization.savedAddPlacementDescription
        }

        if preview == nil {
            if isEditing {
                return SourceManagementLocalization.editPendingPlacementDescription
            }
            return SourceManagementLocalization.addPendingPlacementDescription
        }

        if availableFolders.isEmpty {
            return SourceManagementLocalization.noFoldersPlacementDescription
        }

        return isEditing
            ? SourceManagementLocalization.editReadyPlacementDescription
            : SourceManagementLocalization.addReadyPlacementDescription
    }

    private func placementOptions() -> [SourceManagementFolderPlacementOptionPresentation] {
        guard createdFeed == nil,
              isCreatingFeed == false,
              hasDuplicateConflict == false,
              isEditing == false,
              preview != nil || isEditing else { return [] }

        return [
            SourceManagementFolderPlacementOptionPresentation(
                placement: .ungrouped,
                title: SourceManagementLocalization.ungroupedTitle,
                subtitle: SourceManagementLocalization.ungroupedSubtitle,
                trailingValue: nil,
                isSelected: selectedFolderPlacement == .ungrouped
            )
        ] + availableFolders.map { folder in
            SourceManagementFolderPlacementOptionPresentation(
                placement: .folder(folder.id),
                title: folder.name,
                subtitle: SourceManagementLocalization.existingFeedCount(folder.feedCount),
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
        return SourceManagementLocalization.createNewFolderAction
    }

    private func selectedPlacementTitle() -> String {
        switch selectedFolderPlacement {
        case .ungrouped:
            return SourceManagementLocalization.ungroupedTitle
        case .folder(let folderID):
            return availableFolders.first(where: { $0.id == folderID })?.name
                ?? SourceManagementLocalization.selectedFolderTitle
        }
    }

    private func kindTitle(_ kind: FeedKind) -> String {
        switch kind {
        case .rss:
            return "RSS"
        case .atom:
            return "Atom"
        case .unknown:
            return SourceManagementLocalization.unknownFeedKindTitle
        }
    }

    private func folderSortComparator(
        lhs: SourceManagementFolderSummary,
        rhs: SourceManagementFolderSummary
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
