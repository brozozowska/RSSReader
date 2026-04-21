import Foundation

struct SourceManagementScreenState {
    private(set) var summary = SourceManagementScreenPresentationBuilder.buildSummary()
    private(set) var sections = SourceManagementScreenPresentationBuilder.buildSections()
    private(set) var presentedDestination: SourceManagementScreenDestinationPresentation? = nil
    private(set) var addFeedState = SourceManagementAddFeedState()
    private(set) var createFolderState = SourceManagementCreateFolderState()

    mutating func presentScenario(_ scenarioID: SourceManagementScenarioID) {
        switch scenarioID {
        case .addFeed:
            presentedDestination = .addFeed(addFeedState.derivedPresentation())
        case .createFolder:
            presentedDestination = .createFolder(createFolderState.derivedPresentation())
        case .moveSource:
            presentedDestination = .placeholder(
                SourceManagementScreenPresentationBuilder.buildDestination(for: scenarioID)
            )
        }
    }

    mutating func dismissPresentedScenario() {
        presentedDestination = nil
    }

    mutating func updateAddFeedURLInput(_ value: String) {
        addFeedState.updateURLInput(value)
        refreshPresentedDestination()
    }

    mutating func prepareAddFeedPreview() {
        addFeedState.preparePreviewRequest()
        refreshPresentedDestination()
    }

    func addFeedValidationMessage() -> String? {
        addFeedState.validationMessage()
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
        preparedPreviewURL: String? = nil
    ) -> SourceManagementScreenState {
        var state = SourceManagementScreenState()
        state.updateAddFeedURLInput(urlInput)
        if preparedPreviewURL != nil {
            state.addFeedState.preparePreviewRequest()
        }
        state.presentScenario(.addFeed)
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
    private(set) var preparedPreviewURL: String? = nil

    mutating func updateURLInput(_ value: String) {
        urlInput = value
        preparedPreviewURL = nil
    }

    mutating func preparePreviewRequest() {
        guard let normalizedURL = normalizedValidatedURL() else { return }
        preparedPreviewURL = normalizedURL
    }

    func derivedPresentation() -> SourceManagementAddFeedPresentation {
        let validationMessage = validationMessage()
        let normalizedURL = normalizedValidatedURL()
        let isPrepared = preparedPreviewURL != nil

        return SourceManagementAddFeedPresentation(
            title: "Add Feed",
            summaryTitle: "Feed Setup",
            summaryDescription: "Prepare and validate the feed URL locally before the app starts any network preview work.",
            urlInput: urlInput,
            urlPrompt: "Feed URL",
            validationMessage: validationMessage,
            normalizedURL: normalizedURL,
            primaryActionTitle: isPrepared ? "Preview Prepared" : "Prepare Preview",
            isPrimaryActionEnabled: validationMessage == nil && isPrepared == false,
            preparedPreview: preparedPreviewPresentation()
        )
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

    private func normalizedURLInput() -> String {
        urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedValidatedURL() -> String? {
        guard validationMessage() == nil else { return nil }
        return URL(string: normalizedURLInput())?.absoluteString
    }

    private func preparedPreviewPresentation() -> SourceManagementAddFeedPreparedPreviewPresentation? {
        guard let preparedPreviewURL else { return nil }

        return SourceManagementAddFeedPreparedPreviewPresentation(
            title: "Preview request is prepared",
            detail: "The URL is normalized and ready for the network preview step that will be connected next.",
            normalizedURL: preparedPreviewURL
        )
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
