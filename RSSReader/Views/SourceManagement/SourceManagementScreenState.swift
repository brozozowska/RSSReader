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

    mutating func selectAddFeedFolderPlacement(
        _ placement: SourceManagementFolderPlacement
    ) {
        addFeedState.selectFolderPlacement(placement)
        refreshPresentedDestination()
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

    mutating func applyCreateFolderServiceUnavailable(message: String) {
        createFolderState.applyServiceUnavailable(message: message)
        refreshPresentedDestination()
    }

    mutating func updateCreateFolderNameInput(_ value: String) {
        createFolderState.updateNameInput(value)
        refreshPresentedDestination()
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

    func moveSourceCommand() -> SourceManagementMoveFeedCommand? {
        moveSourceState.moveCommand()
    }

    func derivedViewState() -> SourceManagementScreenViewState {
        SourceManagementScreenViewState(
            summary: summary,
            sections: sections,
            presentedDestination: presentedDestination
        )
    }

    static func previewLoaded(
        presentedScenarioID: SourceManagementScenarioID? = nil
    ) -> SourceManagementScreenState {
        var state = SourceManagementScreenState()
        if let presentedScenarioID {
            state.presentScenario(presentedScenarioID)
        }
        return state
    }

    static func previewAddFeed(
        urlInput: String = "",
        preview: SourceManagementFeedPreview? = nil,
        isConfirmed: Bool = false,
        failureMessage: String? = nil,
        folders: [SourceManagementFolderSummary] = [],
        selectedPlacement: SourceManagementFolderPlacement = .ungrouped
    ) -> SourceManagementScreenState {
        var state = SourceManagementScreenState()
        state.updateAddFeedURLInput(urlInput)
        state.applyAddFeedFolderContext(folders: folders)
        state.selectAddFeedFolderPlacement(selectedPlacement)
        if let preview {
            let requestURL = preview.requestedURL
            _ = state.beginAddFeedPreviewLoading()
            state.applyLoadedAddFeedPreview(preview, requestURL: requestURL)
            if isConfirmed {
                state.confirmAddFeedPreview()
            }
        } else if let failureMessage {
            let requestURL = state.beginAddFeedPreviewLoading()
            state.applyAddFeedPreviewFailure(
                SourceManagementAddFeedStatusPresentation(
                    title: "Preview could not be loaded",
                    kind: .failure,
                    detail: failureMessage
                ),
                requestURL: requestURL
            )
        }
        state.presentScenario(.addFeed)
        return state
    }

    static func previewMoveSource(
        feeds: [SourceManagementFeedSummary] = [],
        folders: [SourceManagementFolderSummary] = []
    ) -> SourceManagementScreenState {
        var state = SourceManagementScreenState()
        state.applyMoveSourceContext(feeds: feeds, folders: folders)
        state.presentScenario(.moveSource)
        return state
    }

    static func previewCreateFolder(
        nameInput: String = "",
        feedback: SourceManagementCreateFolderFeedbackPresentation? = nil
    ) -> SourceManagementScreenState {
        var state = SourceManagementScreenState()
        state.applyCreateFolderContext(
            folders: [
                SourceManagementFolderSummary(
                    id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                    name: "News",
                    sortOrder: 0,
                    feedCount: 12
                ),
                SourceManagementFolderSummary(
                    id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                    name: "Tech",
                    sortOrder: 1,
                    feedCount: 8
                )
            ]
        )
        state.updateCreateFolderNameInput(nameInput)
        if let feedback {
            state.createFolderState.feedback = feedback
        }
        state.presentScenario(.createFolder)
        return state
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

        guard let request = try? FeedRequest(
            feedID: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            urlString: normalizedInput
        ) else {
            return "Enter a valid http or https URL."
        }

        guard let components = URLComponents(
            url: request.url,
            resolvingAgainstBaseURL: false
        ), let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = components.host,
              host.isEmpty == false else {
            return "Enter a valid http or https URL."
        }

        return nil
    }

    func canConfirmPreview() -> Bool {
        preview != nil
            && isPreviewConfirmed == false
            && isLoadingPreview == false
            && isCreatingFeed == false
            && createdFeed == nil
    }

    func canCreateFeed() -> Bool {
        preview != nil
            && preview?.existingFeedID == nil
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
        guard preview != nil else { return }
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

    mutating func applyCreatedFeed(_ feed: SourceManagementFeedSummary) {
        createdFeed = feed
        isCreatingFeed = false
        previewStatus = SourceManagementAddFeedStatusPresentation(
            title: "Feed added",
            kind: .success,
            detail: "\(feed.title) was saved in \(feed.folderName ?? "Ungrouped")."
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
            primaryActionTitle = "Adding Feed..."
            isPrimaryActionEnabled = false
        } else if createdFeed != nil {
            primaryActionTitle = "Feed Added"
            isPrimaryActionEnabled = false
        } else if preview != nil {
            if preview?.existingFeedID != nil {
                primaryActionTitle = "Already Added"
                isPrimaryActionEnabled = false
            } else {
                primaryActionTitle = isPreviewConfirmed ? "Add Feed" : "Confirm Feed"
                isPrimaryActionEnabled = true
            }
        } else {
            primaryActionTitle = "Preview Feed"
            isPrimaryActionEnabled = validationMessage == nil
        }

        return SourceManagementAddFeedPresentation(
            title: "Add Feed",
            summaryTitle: "Feed Setup",
            summaryDescription: "Preview the feed metadata before you commit to adding this source.",
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
            createFolderActionTitle: preview?.existingFeedID == nil && createdFeed == nil && isCreatingFeed == false
                ? "Create New Folder"
                : nil,
            status: statusPresentation()
        )
    }

    private func normalizedURLInput() -> String {
        urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedValidatedURL() -> String? {
        guard validationMessage() == nil else { return nil }
        return URL(string: normalizedURLInput())?.absoluteString
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
            existingFeedNotice: preview.existingFeedID == nil
                ? nil
                : "This source already exists in the library.",
            diagnosticsSummary: diagnosticsSummary(preview: preview)
        )
    }

    private func statusPresentation() -> SourceManagementAddFeedStatusPresentation? {
        if let previewStatus {
            return previewStatus
        }

        if preview?.existingFeedID != nil {
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
            detail: "The feed metadata is confirmed and ready for the feed-creation step in \(selectedPlacementTitle())."
        )
    }

    private func placementDescription() -> String {
        if createdFeed != nil {
            return "The source has already been saved. Edit the URL to start a new add-feed flow."
        }

        if preview == nil {
            return "Preview the feed first, then choose whether the source should stay ungrouped or land in a folder."
        }

        if availableFolders.isEmpty {
            return "No folders are available yet. The source can stay ungrouped until you create a folder in Source Management."
        }

        return "Choose where the source should live once the feed-creation step saves it."
    }

    private func placementOptions() -> [SourceManagementFolderPlacementOptionPresentation] {
        guard preview?.existingFeedID == nil,
              createdFeed == nil,
              isCreatingFeed == false else { return [] }

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

    private func selectedFeed() -> SourceManagementFeedSummary? {
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

    mutating func applyServiceUnavailable(message: String) {
        existingFolders = []
        isServiceAvailable = false
        isSubmitting = false
        feedback = SourceManagementCreateFolderFeedbackPresentation(
            kind: .failure,
            title: "Folder creation is unavailable",
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

    mutating func applyCreatedFolder(_ folder: SourceManagementFolderSummary) {
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
        nameInput = ""
        isSubmitting = false
        feedback = SourceManagementCreateFolderFeedbackPresentation(
            kind: .success,
            title: "Folder created",
            detail: "\"\(folder.name)\" will appear as sidebar folder #\(folder.sortOrder + 1)."
        )
    }

    mutating func applySubmissionFailure(message: String) {
        isSubmitting = false
        feedback = SourceManagementCreateFolderFeedbackPresentation(
            kind: .failure,
            title: "Folder could not be created",
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
            title: "Create Folder",
            summaryTitle: "Folder Setup",
            summaryDescription: "Create a reusable folder first when you want sidebar grouping to exist before any feed is assigned to it.",
            nameInput: nameInput,
            namePrompt: "Folder Name",
            validationMessage: validationMessage,
            existingFolders: existingFolderPresentations,
            placementDescription: placementDescription(for: nextSortOrder),
            primaryActionTitle: isSubmitting ? "Creating..." : "Create Folder",
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

        if existingFolders.contains(where: { $0.name == normalizedValue }) {
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
        if existingFolders.isEmpty {
            return "This will become the first sidebar folder."
        }

        return "The next compatible sidebar position is #\(sortOrder + 1), after \(existingFolders.count) existing folder(s)."
    }
}
