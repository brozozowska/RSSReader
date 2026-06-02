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
            return "Enter a feed URL to continue."
        }

        guard (try? SourceManagementFeedDiscoveryPlanner.makePlan(for: normalizedInput)) != nil else {
            return "Enter a valid site or feed URL."
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
            title: wasEditing ? "Feed updated" : "Feed added",
            kind: .success,
            detail: wasEditing
                ? "\(feed.title) now points to \(feed.url) in \(feed.folderName ?? "Ungrouped")."
                : "\(feed.title) was saved in \(feed.folderName ?? "Ungrouped")."
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
            primaryActionTitle = "Loading Preview..."
            isPrimaryActionEnabled = false
        } else if isCreatingFeed {
            primaryActionTitle = isEditing ? "Saving Changes..." : "Adding Feed..."
            isPrimaryActionEnabled = false
        } else if createdFeed != nil {
            primaryActionTitle = isEditing ? "Changes Saved" : "Feed Added"
            isPrimaryActionEnabled = false
        } else if previewStatus?.kind == .failure {
            primaryActionTitle = "Preview Feed"
            isPrimaryActionEnabled = false
        } else if canUpdateDisplayNameWithoutPreview() {
            primaryActionTitle = "Save Changes"
            isPrimaryActionEnabled = true
        } else if preview != nil {
            if hasDuplicateConflict {
                primaryActionTitle = "Already Added"
                isPrimaryActionEnabled = false
            } else {
                primaryActionTitle = isEditing ? "Save Changes" : "Add Feed"
                isPrimaryActionEnabled = true
            }
        } else {
            primaryActionTitle = "Preview Feed"
            isPrimaryActionEnabled = validationMessage == nil
        }
        let isConfirmationActionEnabled = (preview != nil || canUpdateDisplayNameWithoutPreview())
            && hasDuplicateConflict == false
            && isLoadingPreview == false
            && isCreatingFeed == false
            && createdFeed == nil

        return SourceManagementAddFeedPresentation(
            title: isEditing ? "Edit Feed" : "Add Feed",
            summaryTitle: isEditing ? "Source Details" : "New Source",
            summaryDescription: isEditing
                ? "Change the display name, or preview a new feed address when the source has moved."
                : "Enter a website or feed address. The app will look for a readable feed before you add it.",
            urlInput: urlInput,
            urlPrompt: "Feed URL",
            displayNameInput: displayNameInput,
            displayNamePrompt: "Display Name",
            displayNameFooter: displayNameFooter(),
            showsDisplayNameInput: showsDisplayNameInput(),
            validationMessage: validationMessage,
            normalizedURL: normalizedURL,
            primaryActionTitle: primaryActionTitle,
            isPrimaryActionEnabled: isPrimaryActionEnabled,
            isConfirmationActionEnabled: isConfirmationActionEnabled,
            isLoadingPreview: isLoadingPreview,
            preview: previewPresentation(),
            placementTitle: "Destination Folder",
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
            return "Set the name shown for this source in Sources and article lists."
        }
        return "Leave the feed title unchanged, or choose a custom name for this source."
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
                ? "This source already exists in the library."
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
                title: "This feed is already in the library",
                kind: .warning,
                detail: "Use the existing source instead of creating a duplicate subscription."
            )
        }

        return nil
    }

    private func placementDescription() -> String {
        if createdFeed != nil {
            return isEditing
                ? "The source has already been updated. Edit the URL to start another edit flow."
                : "The source has already been saved. Edit the URL to start a new add-feed flow."
        }

        if preview == nil {
            if isEditing {
                return "The current folder is preselected. Review the source before saving changes."
            }
            return "Review the source first, then choose whether it should stay ungrouped or live in a folder."
        }

        if availableFolders.isEmpty {
            return "No folders are available yet. You can keep the source ungrouped or create a folder."
        }

        return isEditing
            ? "Choose where this source should appear after saving."
            : "Choose where this source should appear after adding it."
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
                title: "Ungrouped",
                subtitle: "Keep the source outside any folder.",
                trailingValue: nil,
                isSelected: selectedFolderPlacement == .ungrouped
            )
        ] + availableFolders.map { folder in
            SourceManagementFolderPlacementOptionPresentation(
                placement: .folder(folder.id),
                title: folder.name,
                subtitle: folder.feedCount == 1
                    ? "1 existing feed"
                    : "\(folder.feedCount) existing feeds",
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
        return "Create New Folder"
    }

    private func selectedPlacementTitle() -> String {
        switch selectedFolderPlacement {
        case .ungrouped:
            return "Ungrouped"
        case .folder(let folderID):
            return availableFolders.first(where: { $0.id == folderID })?.name ?? "Selected Folder"
        }
    }

    private func kindTitle(_ kind: FeedKind) -> String {
        switch kind {
        case .rss:
            return "RSS"
        case .atom:
            return "Atom"
        case .unknown:
            return "Unknown"
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
