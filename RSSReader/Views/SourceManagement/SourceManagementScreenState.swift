import Foundation

struct SourceManagementScreenState {
    private(set) var summary = SourceManagementScreenPresentationBuilder.buildSummary()
    private(set) var sections = SourceManagementScreenPresentationBuilder.buildSections()
    private(set) var presentedDestination: SourceManagementScreenDestinationPresentation? = nil
    private(set) var addFeedState = SourceManagementAddFeedState()
    private(set) var moveSourceState = SourceManagementMoveSourceState()
    private(set) var createFolderState = SourceManagementCreateFolderState()

    mutating func presentScenario(_ scenarioID: SourceManagementScenarioID) {
        switch scenarioID {
        case .addFeed:
            presentedDestination = .addFeed(addFeedState.derivedPresentation())
        case .createFolder:
            presentedDestination = .createFolder(createFolderState.derivedPresentation())
        case .moveSource:
            presentedDestination = .moveSource(moveSourceState.derivedPresentation())
        }
    }

    mutating func dismissPresentedScenario() {
        presentedDestination = nil
    }

    mutating func updateAddFeedURLInput(_ value: String) {
        addFeedState.updateURLInput(value)
        refreshPresentedDestination()
    }

    func addFeedValidationMessage() -> String? {
        addFeedState.validationMessage()
    }

    func addFeedCanConfirmPreview() -> Bool {
        addFeedState.canConfirmPreview()
    }

    mutating func beginAddFeedPreviewLoading() -> String? {
        let requestURL = addFeedState.beginPreviewLoading()
        refreshPresentedDestination()
        return requestURL
    }

    mutating func applyLoadedAddFeedPreview(
        _ preview: SourceManagementFeedPreview,
        requestURL: String
    ) {
        addFeedState.applyLoadedPreview(preview, requestURL: requestURL)
        refreshPresentedDestination()
    }

    mutating func applyAddFeedPreviewFailure(
        _ status: SourceManagementAddFeedStatusPresentation,
        requestURL: String?
    ) {
        addFeedState.applyPreviewFailure(status: status, requestURL: requestURL)
        refreshPresentedDestination()
    }

    mutating func confirmAddFeedPreview() {
        addFeedState.confirmPreview()
        refreshPresentedDestination()
    }

    mutating func beginAddFeedCreation() -> SourceManagementCreateFeedCommand? {
        let command = addFeedState.beginFeedCreation()
        refreshPresentedDestination()
        return command
    }

    mutating func applyCreatedAddFeed(_ feed: SourceManagementFeedSummary) {
        addFeedState.applyCreatedFeed(feed)
        refreshPresentedDestination()
    }

    mutating func applyAddFeedCreationFailure(
        _ status: SourceManagementAddFeedStatusPresentation
    ) {
        addFeedState.applyFeedCreationFailure(status: status)
        refreshPresentedDestination()
    }

    mutating func applyAddFeedFolderContext(
        folders: [SourceManagementFolderSummary]
    ) {
        addFeedState.applyAvailableFolders(folders)
        refreshPresentedDestination()
    }

    mutating func resetAddFeedForEntry() {
        addFeedState.resetForEntry()
        refreshPresentedDestination()
    }

    mutating func selectAddFeedFolderPlacement(
        _ placement: SourceManagementFolderPlacement
    ) {
        addFeedState.selectFolderPlacement(placement)
        refreshPresentedDestination()
    }

    mutating func applyAddFeedEditContext(
        feed: SourceManagementFeedSummary,
        folders: [SourceManagementFolderSummary]
    ) {
        addFeedState.applyAvailableFolders(folders)
        addFeedState.applyEditingFeed(feed)
        refreshPresentedDestination()
    }

    func isEditingAddFeed() -> Bool {
        addFeedState.isEditing
    }

    mutating func beginAddFeedUpdate() -> SourceManagementUpdateFeedCommand? {
        let command = addFeedState.beginFeedUpdate()
        refreshPresentedDestination()
        return command
    }

    mutating func applyCreateFolderContext(
        folders: [SourceManagementFolderSummary],
        isServiceAvailable: Bool = true
    ) {
        createFolderState.applyAvailableFolders(
            folders,
            isServiceAvailable: isServiceAvailable
        )
        refreshPresentedDestination()
    }

    mutating func resetCreateFolderForEntry() {
        createFolderState.resetForEntry()
        refreshPresentedDestination()
    }

    mutating func applyCreateFolderServiceUnavailable(title: String, message: String) {
        createFolderState.applyServiceUnavailable(title: title, message: message)
        refreshPresentedDestination()
    }

    mutating func updateCreateFolderNameInput(_ value: String) {
        createFolderState.updateNameInput(value)
        refreshPresentedDestination()
    }

    mutating func applyCreateFolderEditContext(
        folder: SourceManagementFolderSummary,
        folders: [SourceManagementFolderSummary]
    ) {
        createFolderState.applyAvailableFolders(
            folders,
            isServiceAvailable: true
        )
        createFolderState.applyEditingFolder(folder)
        refreshPresentedDestination()
    }

    func isEditingCreateFolder() -> Bool {
        createFolderState.isEditing
    }

    mutating func beginCreateFolderUpdate() -> SourceManagementUpdateFolderCommand? {
        let command = createFolderState.beginUpdate()
        refreshPresentedDestination()
        return command
    }

    mutating func beginCreateFolderSubmission() {
        createFolderState.beginSubmission()
        refreshPresentedDestination()
    }

    mutating func applyMoveSourceContext(
        feeds: [SourceManagementFeedSummary],
        folders: [SourceManagementFolderSummary]
    ) {
        moveSourceState.applyContext(feeds: feeds, folders: folders)
        refreshPresentedDestination()
    }

    mutating func selectMoveSourceFeed(_ feedID: UUID) {
        moveSourceState.selectFeed(feedID)
        refreshPresentedDestination()
    }

    mutating func selectMoveSourcePlacement(
        _ placement: SourceManagementFolderPlacement
    ) {
        moveSourceState.selectPlacement(placement)
        refreshPresentedDestination()
    }

    mutating func beginMoveSourceSubmission() {
        moveSourceState.beginSubmission()
        refreshPresentedDestination()
    }

    mutating func applyMovedSource(_ feed: SourceManagementFeedSummary) {
        moveSourceState.applyMovedFeed(feed)
        refreshPresentedDestination()
    }

    mutating func applyMoveSourceFailure(_ message: String) {
        moveSourceState.applyFailure(message: message)
        refreshPresentedDestination()
    }

    mutating func applyCreatedFolder(_ folder: SourceManagementFolderSummary) {
        createFolderState.applyCreatedFolder(folder)
        refreshPresentedDestination()
    }

    mutating func applyCreateFolderFailure(_ message: String) {
        createFolderState.applySubmissionFailure(message: message)
        refreshPresentedDestination()
    }

    func createFolderNameInput() -> String {
        createFolderState.nameInput
    }

    func createFolderValidationMessage() -> String? {
        createFolderState.validationMessage()
    }

    func createFolderEditingName() -> String? {
        createFolderState.editingName
    }

    func moveSourceCommand() -> SourceManagementMoveFeedCommand? {
        moveSourceState.moveCommand()
    }

    func selectedMoveSourceFeed() -> SourceManagementFeedSummary? {
        moveSourceState.selectedFeed()
    }

    func derivedViewState() -> SourceManagementScreenViewState {
        SourceManagementScreenViewState(
            summary: summary,
            sections: sections,
            presentedDestination: presentedDestination
        )
    }

    private mutating func refreshPresentedDestination() {
        guard let presentedDestination else { return }
        presentScenario(presentedDestination.id)
    }
}

struct SourceManagementAddFeedState {
    private(set) var urlInput = ""
    private(set) var isLoadingPreview = false
    private(set) var isCreatingFeed = false
    private(set) var activePreviewRequestURL: String? = nil
    private(set) var preview: SourceManagementFeedPreview? = nil
    private(set) var isPreviewConfirmed = false
    private(set) var createdFeed: SourceManagementFeedSummary? = nil
    private(set) var previewStatus: SourceManagementAddFeedStatusPresentation? = nil
    private(set) var availableFolders: [SourceManagementFolderSummary] = []
    private(set) var selectedFolderPlacement: SourceManagementFolderPlacement = .ungrouped
    private(set) var editingFeed: SourceManagementFeedSummary? = nil

    var isEditing: Bool {
        editingFeed != nil
    }

    mutating func updateURLInput(_ value: String) {
        urlInput = value
        isLoadingPreview = false
        isCreatingFeed = false
        activePreviewRequestURL = nil
        preview = nil
        isPreviewConfirmed = false
        createdFeed = nil
        previewStatus = nil
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
        isLoadingPreview = false
        isCreatingFeed = false
        activePreviewRequestURL = nil
        preview = nil
        isPreviewConfirmed = false
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
        isLoadingPreview = false
        isCreatingFeed = false
        activePreviewRequestURL = nil
        preview = nil
        isPreviewConfirmed = false
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

    func canConfirmPreview() -> Bool {
        preview != nil
            && hasDuplicateConflict == false
            && isPreviewConfirmed == false
            && isLoadingPreview == false
            && isCreatingFeed == false
            && createdFeed == nil
    }

    func canCreateFeed() -> Bool {
        preview != nil
            && editingFeed == nil
            && hasDuplicateConflict == false
            && isPreviewConfirmed
            && isLoadingPreview == false
            && isCreatingFeed == false
            && createdFeed == nil
    }

    func canUpdateFeed() -> Bool {
        preview != nil
            && editingFeed != nil
            && hasDuplicateConflict == false
            && isPreviewConfirmed
            && isLoadingPreview == false
            && isCreatingFeed == false
            && createdFeed == nil
    }

    mutating func beginPreviewLoading() -> String? {
        guard let normalizedURL = normalizedValidatedURL() else { return nil }

        isLoadingPreview = true
        isCreatingFeed = false
        activePreviewRequestURL = normalizedURL
        preview = nil
        isPreviewConfirmed = false
        createdFeed = nil
        previewStatus = nil
        return normalizedURL
    }

    mutating func applyLoadedPreview(
        _ preview: SourceManagementFeedPreview,
        requestURL: String
    ) {
        guard activePreviewRequestURL == requestURL else { return }

        self.preview = preview
        isLoadingPreview = false
        isCreatingFeed = false
        activePreviewRequestURL = nil
        previewStatus = nil
        isPreviewConfirmed = false
        createdFeed = nil
    }

    mutating func applyPreviewFailure(
        status: SourceManagementAddFeedStatusPresentation,
        requestURL: String?
    ) {
        guard requestURL == nil || activePreviewRequestURL == requestURL else { return }

        isLoadingPreview = false
        isCreatingFeed = false
        activePreviewRequestURL = nil
        preview = nil
        isPreviewConfirmed = false
        createdFeed = nil
        previewStatus = status
    }

    mutating func confirmPreview() {
        guard preview != nil, hasDuplicateConflict == false else { return }
        isPreviewConfirmed = true
        previewStatus = nil
    }

    mutating func beginFeedCreation() -> SourceManagementCreateFeedCommand? {
        guard canCreateFeed(), let preview else { return nil }

        isCreatingFeed = true
        previewStatus = nil

        return SourceManagementCreateFeedCommand(
            preview: preview,
            folderPlacement: selectedFolderPlacement
        )
    }

    mutating func beginFeedUpdate() -> SourceManagementUpdateFeedCommand? {
        guard canUpdateFeed(), let preview, let editingFeed else { return nil }

        isCreatingFeed = true
        previewStatus = nil

        return SourceManagementUpdateFeedCommand(
            feedID: editingFeed.id,
            preview: preview,
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
        } else if preview != nil {
            if hasDuplicateConflict {
                primaryActionTitle = "Already Added"
                isPrimaryActionEnabled = false
            } else {
                primaryActionTitle = isPreviewConfirmed
                    ? (isEditing ? "Save Changes" : "Add Feed")
                    : (isEditing ? "Confirm Changes" : "Confirm Feed")
                isPrimaryActionEnabled = true
            }
        } else {
            primaryActionTitle = "Preview Feed"
            isPrimaryActionEnabled = validationMessage == nil
        }

        return SourceManagementAddFeedPresentation(
            title: isEditing ? "Edit Feed" : "Add Feed",
            summaryTitle: isEditing ? "Feed Details" : "Feed Setup",
            summaryDescription: isEditing
                ? "Update the source URL or destination folder, then load a fresh preview before saving the changes."
                : "Preview the feed metadata before you commit to adding this source.",
            urlInput: urlInput,
            urlPrompt: "Feed URL",
            validationMessage: validationMessage,
            normalizedURL: normalizedURL,
            primaryActionTitle: primaryActionTitle,
            isPrimaryActionEnabled: isPrimaryActionEnabled,
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

    private func normalizedValidatedURL() -> String? {
        guard validationMessage() == nil else { return nil }
        return SourceManagementFeedDiscoveryPlanner.displayURLString(for: normalizedURLInput())
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
            diagnosticsSummary: diagnosticsSummary(preview: preview)
        )
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

        guard preview != nil, isPreviewConfirmed else { return nil }
        return SourceManagementAddFeedStatusPresentation(
            title: "Preview confirmed",
            kind: .success,
            detail: isEditing
                ? "The updated feed metadata is confirmed and ready to save in \(selectedPlacementTitle())."
                : "The feed metadata is confirmed and ready for the feed-creation step in \(selectedPlacementTitle())."
        )
    }

    private func placementDescription() -> String {
        if createdFeed != nil {
            return isEditing
                ? "The source has already been updated. Edit the URL to start another edit flow."
                : "The source has already been saved. Edit the URL to start a new add-feed flow."
        }

        if preview == nil {
            if isEditing {
                return "The current destination is preselected. Load a fresh preview before saving the updated source."
            }
            return "Preview the feed first, then choose whether the source should stay ungrouped or land in a folder."
        }

        if availableFolders.isEmpty {
            return "No folders are available yet. The source can stay ungrouped until you create a folder in Source Management."
        }

        return isEditing
            ? "Choose where the existing source should live once the updated feed details are saved."
            : "Choose where the source should live once the feed-creation step saves it."
    }

    private func placementOptions() -> [SourceManagementFolderPlacementOptionPresentation] {
        guard createdFeed == nil,
              isCreatingFeed == false,
              hasDuplicateConflict == false,
              preview != nil || isEditing else { return [] }

        return [
            SourceManagementFolderPlacementOptionPresentation(
                placement: .ungrouped,
                title: "Ungrouped",
                subtitle: "Keep the source outside any folder.",
                isSelected: selectedFolderPlacement == .ungrouped
            )
        ] + availableFolders.map { folder in
            SourceManagementFolderPlacementOptionPresentation(
                placement: .folder(folder.id),
                title: folder.name,
                subtitle: folder.feedCount == 1
                    ? "1 existing feed"
                    : "\(folder.feedCount) existing feeds",
                isSelected: selectedFolderPlacement == .folder(folder.id)
            )
        }
    }

    private func createFolderActionTitle() -> String? {
        guard createdFeed == nil,
              isCreatingFeed == false,
              hasDuplicateConflict == false,
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

    private func diagnosticsSummary(preview: SourceManagementFeedPreview) -> String? {
        let anomalyCount = preview.parserAnomalyCount
        let rejectedCount = preview.rejectedEntryCount
        guard anomalyCount > 0 || rejectedCount > 0 else { return nil }

        return "Parser anomalies: \(anomalyCount). Rejected entries: \(rejectedCount)."
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

struct SourceManagementMoveSourceState {
    private(set) var feeds: [SourceManagementFeedSummary] = []
    private(set) var folders: [SourceManagementFolderSummary] = []
    private(set) var selectedFeedID: UUID? = nil
    private(set) var selectedPlacement: SourceManagementFolderPlacement = .ungrouped
    private(set) var isSubmitting = false
    fileprivate(set) var feedback: SourceManagementMoveSourceFeedbackPresentation? = nil

    mutating func applyContext(
        feeds: [SourceManagementFeedSummary],
        folders: [SourceManagementFolderSummary]
    ) {
        self.feeds = feeds.sorted(by: feedSortComparator)
        self.folders = folders.sorted(by: folderSortComparator)

        if let selectedFeedID,
           self.feeds.contains(where: { $0.id == selectedFeedID }) {
            selectedPlacement = currentPlacement(for: selectedFeedID) ?? .ungrouped
        } else {
            self.selectedFeedID = self.feeds.first?.id
            selectedPlacement = currentPlacement(for: self.selectedFeedID) ?? .ungrouped
        }

        isSubmitting = false
        if feedback?.kind == .failure {
            feedback = nil
        }
    }

    mutating func selectFeed(_ feedID: UUID) {
        guard feeds.contains(where: { $0.id == feedID }) else { return }
        selectedFeedID = feedID
        selectedPlacement = currentPlacement(for: feedID) ?? .ungrouped
        isSubmitting = false
        feedback = nil
    }

    mutating func selectPlacement(_ placement: SourceManagementFolderPlacement) {
        switch placement {
        case .ungrouped:
            selectedPlacement = .ungrouped
        case .folder(let folderID):
            guard folders.contains(where: { $0.id == folderID }) else { return }
            selectedPlacement = .folder(folderID)
        }
        feedback = nil
    }

    mutating func beginSubmission() {
        isSubmitting = true
        feedback = nil
    }

    mutating func applyMovedFeed(_ feed: SourceManagementFeedSummary) {
        guard let index = feeds.firstIndex(where: { $0.id == feed.id }) else { return }
        feeds[index] = feed
        feeds.sort(by: feedSortComparator)
        selectedFeedID = feed.id
        selectedPlacement = currentPlacement(for: feed.id) ?? .ungrouped
        isSubmitting = false
        feedback = SourceManagementMoveSourceFeedbackPresentation(
            kind: .success,
            title: "Source moved",
            detail: "\(feed.title) now lives in \(placementTitle(for: selectedPlacement))."
        )
    }

    mutating func applyFailure(message: String) {
        isSubmitting = false
        feedback = SourceManagementMoveSourceFeedbackPresentation(
            kind: .failure,
            title: "Source could not be moved",
            detail: message
        )
    }

    func derivedPresentation() -> SourceManagementMoveSourcePresentation {
        let selectedFeedTitle = selectedFeed().map(\.title)
        let canSubmit = selectedFeedID != nil
            && currentPlacement(for: selectedFeedID) != nil
            && currentPlacement(for: selectedFeedID) != selectedPlacement
            && isSubmitting == false

        return SourceManagementMoveSourcePresentation(
            title: "Move Sources",
            summaryTitle: "Source Organization",
            summaryDescription: "Select an existing feed and move it between folders or return it to the ungrouped area.",
            feeds: feeds.map { feed in
                SourceManagementMoveSourceFeedPresentation(
                    id: feed.id,
                    title: feed.title,
                    subtitle: feed.url,
                    currentPlacementTitle: placementTitle(for: placement(for: feed)),
                    isSelected: feed.id == selectedFeedID
                )
            },
            emptyStateTitle: feeds.isEmpty ? "No existing feeds yet" : nil,
            emptyStateDescription: feeds.isEmpty
                ? "Add and save a source first, then return here to reorganize it."
                : nil,
            placementTitle: "Target Folder",
            placementDescription: placementDescription(for: selectedFeedTitle),
            placementOptions: placementOptions(),
            primaryActionTitle: isSubmitting ? "Moving..." : "Move Source",
            isPrimaryActionEnabled: canSubmit,
            isSubmitting: isSubmitting,
            feedback: feedback
        )
    }

    func moveCommand() -> SourceManagementMoveFeedCommand? {
        guard let selectedFeedID,
              let currentPlacement = currentPlacement(for: selectedFeedID),
              currentPlacement != selectedPlacement else {
            return nil
        }

        return SourceManagementMoveFeedCommand(
            feedID: selectedFeedID,
            folderPlacement: selectedPlacement
        )
    }

    private func placementOptions() -> [SourceManagementFolderPlacementOptionPresentation] {
        guard selectedFeedID != nil else { return [] }

        return [
            SourceManagementFolderPlacementOptionPresentation(
                placement: .ungrouped,
                title: "Ungrouped",
                subtitle: "Return the source to the default ungrouped area.",
                isSelected: selectedPlacement == .ungrouped
            )
        ] + folders.map { folder in
            SourceManagementFolderPlacementOptionPresentation(
                placement: .folder(folder.id),
                title: folder.name,
                subtitle: folder.feedCount == 1
                    ? "1 feed currently in this folder"
                    : "\(folder.feedCount) feeds currently in this folder",
                isSelected: selectedPlacement == .folder(folder.id)
            )
        }
    }

    private func placementDescription(for selectedFeedTitle: String?) -> String {
        guard let selectedFeedTitle else {
            return "Select a feed first, then choose the target folder or the ungrouped destination."
        }

        return "Choose where \(selectedFeedTitle) should live after the move completes."
    }

    func selectedFeed() -> SourceManagementFeedSummary? {
        guard let selectedFeedID else { return nil }
        return feeds.first(where: { $0.id == selectedFeedID })
    }

    private func currentPlacement(for feedID: UUID?) -> SourceManagementFolderPlacement? {
        guard let feedID,
              let feed = feeds.first(where: { $0.id == feedID }) else { return nil }
        return placement(for: feed)
    }

    private func placement(for feed: SourceManagementFeedSummary) -> SourceManagementFolderPlacement {
        if let folderID = feed.folderID {
            return .folder(folderID)
        }
        return .ungrouped
    }

    private func placementTitle(for placement: SourceManagementFolderPlacement) -> String {
        switch placement {
        case .ungrouped:
            return "Ungrouped"
        case .folder(let folderID):
            return folders.first(where: { $0.id == folderID })?.name ?? "Selected Folder"
        }
    }

    private func feedSortComparator(
        lhs: SourceManagementFeedSummary,
        rhs: SourceManagementFeedSummary
    ) -> Bool {
        if lhs.title == rhs.title {
            return lhs.id.uuidString < rhs.id.uuidString
        }
        return lhs.title < rhs.title
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

struct SourceManagementCreateFolderState {
    private(set) var nameInput = ""
    private(set) var existingFolders: [SourceManagementFolderSummary] = []
    private(set) var isServiceAvailable = true
    private(set) var isSubmitting = false
    fileprivate(set) var feedback: SourceManagementCreateFolderFeedbackPresentation? = nil
    private(set) var editingFolder: SourceManagementFolderSummary? = nil

    var isEditing: Bool {
        editingFolder != nil
    }

    var editingName: String? {
        editingFolder?.name
    }

    mutating func applyAvailableFolders(
        _ folders: [SourceManagementFolderSummary],
        isServiceAvailable: Bool
    ) {
        self.existingFolders = folders.sorted { lhs, rhs in
            if lhs.sortOrder == rhs.sortOrder {
                if lhs.name == rhs.name {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.name < rhs.name
            }
            return lhs.sortOrder < rhs.sortOrder
        }
        self.isServiceAvailable = isServiceAvailable
        self.isSubmitting = false
        if isServiceAvailable {
            feedback = nil
        }
    }

    mutating func applyEditingFolder(_ folder: SourceManagementFolderSummary) {
        editingFolder = folder
        nameInput = folder.name
        isServiceAvailable = true
        isSubmitting = false
        feedback = nil
    }

    mutating func resetForEntry() {
        nameInput = ""
        isSubmitting = false
        feedback = nil
        editingFolder = nil
    }

    mutating func applyServiceUnavailable(title: String, message: String) {
        existingFolders = []
        isServiceAvailable = false
        isSubmitting = false
        feedback = SourceManagementCreateFolderFeedbackPresentation(
            kind: .failure,
            title: title,
            detail: message
        )
    }

    mutating func updateNameInput(_ value: String) {
        nameInput = value
        isSubmitting = false
        if feedback?.kind == .failure {
            feedback = nil
        }
    }

    mutating func beginSubmission() {
        isSubmitting = true
        feedback = nil
    }

    mutating func beginUpdate() -> SourceManagementUpdateFolderCommand? {
        guard let editingFolder, validationMessage() == nil else { return nil }
        isSubmitting = true
        feedback = nil
        return SourceManagementUpdateFolderCommand(
            folderID: editingFolder.id,
            name: normalizedName()
        )
    }

    mutating func applyCreatedFolder(_ folder: SourceManagementFolderSummary) {
        let wasEditing = isEditing
        existingFolders.removeAll { $0.id == folder.id }
        existingFolders.append(folder)
        existingFolders.sort { lhs, rhs in
            if lhs.sortOrder == rhs.sortOrder {
                if lhs.name == rhs.name {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.name < rhs.name
            }
            return lhs.sortOrder < rhs.sortOrder
        }
        editingFolder = wasEditing ? folder : editingFolder
        nameInput = wasEditing ? folder.name : ""
        isSubmitting = false
        feedback = SourceManagementCreateFolderFeedbackPresentation(
            kind: .success,
            title: wasEditing ? "Folder updated" : "Folder created",
            detail: wasEditing
                ? "\"\(folder.name)\" keeps sidebar position #\(folder.sortOrder + 1)."
                : "\"\(folder.name)\" now appears as sidebar folder #\(folder.sortOrder + 1)."
        )
    }

    mutating func applySubmissionFailure(message: String) {
        isSubmitting = false
        feedback = SourceManagementCreateFolderFeedbackPresentation(
            kind: .failure,
            title: isEditing ? "Folder could not be updated" : "Folder could not be created",
            detail: message
        )
    }

    func derivedPresentation() -> SourceManagementCreateFolderPresentation {
        let validationMessage = validationMessage()
        let nextSortOrder = self.nextSortOrder()
        let existingFolderPresentations = existingFolders.map { folder in
            SourceManagementCreateFolderExistingFolderPresentation(
                id: folder.id,
                name: folder.name,
                sortOrder: folder.sortOrder,
                feedCount: folder.feedCount
            )
        }

        return SourceManagementCreateFolderPresentation(
            title: isEditing ? "Edit Folder" : "Create Folder",
            summaryTitle: isEditing ? "Folder Details" : "Folder Setup",
            summaryDescription: isEditing
                ? "Rename the existing folder while keeping the current sidebar grouping intact."
                : "Create a reusable folder first when you want sidebar grouping to exist before any feed is assigned to it.",
            nameInput: nameInput,
            namePrompt: "Folder Name",
            validationMessage: validationMessage,
            existingFolders: existingFolderPresentations,
            emptyStateTitle: existingFolders.isEmpty ? "No folders yet" : nil,
            emptyStateDescription: existingFolders.isEmpty
                ? "Create the first folder and it will appear in the sidebar as soon as the save step finishes."
                : nil,
            placementDescription: placementDescription(for: nextSortOrder),
            primaryActionTitle: isSubmitting
                ? (isEditing ? "Saving Folder..." : "Creating Folder...")
                : (isEditing ? "Save Folder" : "Create Folder"),
            isPrimaryActionEnabled: isServiceAvailable && validationMessage == nil && isSubmitting == false,
            isSubmitting: isSubmitting,
            feedback: feedback
        )
    }

    func validationMessage() -> String? {
        guard isServiceAvailable else {
            return "Folder creation is unavailable in the current app environment."
        }

        let normalizedValue = normalizedName()
        guard normalizedValue.isEmpty == false else {
            return "Enter a folder name to continue."
        }

        if existingFolders.contains(where: {
            $0.name == normalizedValue && $0.id != editingFolder?.id
        }) {
            return "A folder with this name already exists."
        }

        return nil
    }

    private func normalizedName() -> String {
        nameInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func nextSortOrder() -> Int {
        existingFolders
            .map(\.sortOrder)
            .max()
            .map { $0 + 1 } ?? 0
    }

    private func placementDescription(for sortOrder: Int) -> String {
        if let editingFolder {
            return "\"\(editingFolder.name)\" keeps sidebar position #\(editingFolder.sortOrder + 1)."
        }

        if existingFolders.isEmpty {
            return "This folder will become the first sidebar group."
        }

        return "The next compatible sidebar position is #\(sortOrder + 1), after \(existingFolders.count) existing folders."
    }
}
