import Foundation

struct SourceManagementScreenState {
    private(set) var summary = SourceManagementScreenPresentationBuilder.buildSummary()
    private(set) var sections = SourceManagementScreenPresentationBuilder.buildSections()
    private(set) var presentedDestination: SourceManagementScreenDestinationPresentation? = nil
    private(set) var addFeedState = SourceManagementAddFeedState()
    private(set) var moveSourceState = SourceManagementMoveSourceState()
    private(set) var createFolderState = SourceManagementCreateFolderState()

    mutating func presentScenario(_ scenarioID: SourceManagementScenarioID) {
        presentedDestination = destinationPresentation(for: scenarioID)
    }

    mutating func dismissPresentedScenario() {
        presentedDestination = nil
    }

    mutating func updateAddFeedURLInput(_ value: String) {
        addFeedState.updateURLInput(value)
        refreshPresentedDestination()
    }

    mutating func updateAddFeedDisplayNameInput(_ value: String) {
        addFeedState.updateDisplayNameInput(value)
        refreshPresentedDestination()
    }

    func addFeedValidationMessage() -> String? {
        addFeedState.validationMessage()
    }

    func addFeedURLInput() -> String {
        addFeedState.urlInput
    }

    func addFeedDisplayNameInput() -> String {
        addFeedState.displayNameInput
    }

    mutating func beginAddFeedPreviewLoading() -> SourceManagementAddFeedPreviewCommand? {
        let requestURL = addFeedState.beginPreviewLoading()
        refreshPresentedDestination()
        return requestURL
    }

    func shouldPreviewAddFeedBeforeSaving() -> Bool {
        addFeedState.shouldPreviewBeforeSaving()
    }

    mutating func applyLoadedAddFeedPreview(
        _ preview: SourceManagementFeedPreview,
        command: SourceManagementAddFeedPreviewCommand
    ) {
        addFeedState.applyLoadedPreview(preview, command: command)
        refreshPresentedDestination()
    }

    mutating func applyAddFeedPreviewFailure(
        _ status: SourceManagementAddFeedStatusPresentation,
        command: SourceManagementAddFeedPreviewCommand?
    ) {
        addFeedState.applyPreviewFailure(status: status, command: command)
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
        folders: [SourceManagementFolderSummary],
        selectedFeedID: UUID? = nil
    ) {
        moveSourceState.applyContext(
            feeds: feeds,
            folders: folders,
            selectedFeedID: selectedFeedID
        )
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

    func destinationPresentation(
        for scenarioID: SourceManagementScenarioID
    ) -> SourceManagementScreenDestinationPresentation {
        switch scenarioID {
        case .addFeed:
            return .addFeed(addFeedState.derivedPresentation())
        case .createFolder:
            return .createFolder(createFolderState.derivedPresentation())
        case .moveSource:
            return .moveSource(moveSourceState.derivedPresentation())
        }
    }

    private mutating func refreshPresentedDestination() {
        guard let presentedDestination else { return }
        presentScenario(presentedDestination.id)
    }
}
