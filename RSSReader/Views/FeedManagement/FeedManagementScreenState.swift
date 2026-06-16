import Foundation

struct FeedManagementScreenState {
    private(set) var summary = FeedManagementScreenPresentationBuilder.buildSummary()
    private(set) var sections = FeedManagementScreenPresentationBuilder.buildSections()
    private(set) var presentedDestination: FeedManagementScreenDestinationPresentation? = nil
    private(set) var addFeedState = FeedManagementAddFeedState()
    private(set) var moveFeedState = FeedManagementMoveFeedState()
    private(set) var createFolderState = FeedManagementCreateFolderState()

    mutating func presentScenario(_ scenarioID: FeedManagementScenarioID) {
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

    mutating func beginAddFeedPreviewLoading() -> FeedManagementAddFeedPreviewCommand? {
        let requestURL = addFeedState.beginPreviewLoading()
        refreshPresentedDestination()
        return requestURL
    }

    func shouldPreviewAddFeedBeforeSaving() -> Bool {
        addFeedState.shouldPreviewBeforeSaving()
    }

    mutating func applyLoadedAddFeedPreview(
        _ preview: FeedManagementFeedPreview,
        command: FeedManagementAddFeedPreviewCommand
    ) {
        addFeedState.applyLoadedPreview(preview, command: command)
        refreshPresentedDestination()
    }

    mutating func applyAddFeedPreviewFailure(
        _ status: FeedManagementAddFeedStatusPresentation,
        command: FeedManagementAddFeedPreviewCommand?
    ) {
        addFeedState.applyPreviewFailure(status: status, command: command)
        refreshPresentedDestination()
    }

    mutating func beginAddFeedCreation() -> FeedManagementCreateFeedCommand? {
        let command = addFeedState.beginFeedCreation()
        refreshPresentedDestination()
        return command
    }

    mutating func applyCreatedAddFeed(_ feed: FeedManagementFeedSummary) {
        addFeedState.applyCreatedFeed(feed)
        refreshPresentedDestination()
    }

    mutating func applyAddFeedCreationFailure(
        _ status: FeedManagementAddFeedStatusPresentation
    ) {
        addFeedState.applyFeedCreationFailure(status: status)
        refreshPresentedDestination()
    }

    mutating func applyAddFeedFolderContext(
        folders: [FeedManagementFolderSummary]
    ) {
        addFeedState.applyAvailableFolders(folders)
        refreshPresentedDestination()
    }

    mutating func resetAddFeedForEntry() {
        addFeedState.resetForEntry()
        refreshPresentedDestination()
    }

    mutating func selectAddFeedFolderPlacement(
        _ placement: FeedManagementFolderPlacement
    ) {
        addFeedState.selectFolderPlacement(placement)
        refreshPresentedDestination()
    }

    mutating func applyAddFeedEditContext(
        feed: FeedManagementFeedSummary,
        folders: [FeedManagementFolderSummary]
    ) {
        addFeedState.applyAvailableFolders(folders)
        addFeedState.applyEditingFeed(feed)
        refreshPresentedDestination()
    }

    func isEditingAddFeed() -> Bool {
        addFeedState.isEditing
    }

    mutating func beginAddFeedUpdate() -> FeedManagementUpdateFeedCommand? {
        let command = addFeedState.beginFeedUpdate()
        refreshPresentedDestination()
        return command
    }

    mutating func applyCreateFolderContext(
        folders: [FeedManagementFolderSummary],
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
        folder: FeedManagementFolderSummary,
        folders: [FeedManagementFolderSummary]
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

    mutating func beginCreateFolderUpdate() -> FeedManagementUpdateFolderCommand? {
        let command = createFolderState.beginUpdate()
        refreshPresentedDestination()
        return command
    }

    mutating func beginCreateFolderSubmission() {
        createFolderState.beginSubmission()
        refreshPresentedDestination()
    }

    mutating func applyMoveFeedContext(
        feeds: [FeedManagementFeedSummary],
        folders: [FeedManagementFolderSummary],
        selectedFeedID: UUID? = nil
    ) {
        moveFeedState.applyContext(
            feeds: feeds,
            folders: folders,
            selectedFeedID: selectedFeedID
        )
        refreshPresentedDestination()
    }

    mutating func selectMoveFeedFeed(_ feedID: UUID) {
        moveFeedState.selectFeed(feedID)
        refreshPresentedDestination()
    }

    mutating func selectMoveFeedPlacement(
        _ placement: FeedManagementFolderPlacement
    ) {
        moveFeedState.selectPlacement(placement)
        refreshPresentedDestination()
    }

    mutating func beginMoveFeedSubmission() {
        moveFeedState.beginSubmission()
        refreshPresentedDestination()
    }

    mutating func applyMovedFeed(_ feed: FeedManagementFeedSummary) {
        moveFeedState.applyMovedFeed(feed)
        refreshPresentedDestination()
    }

    mutating func applyMoveFeedFailure(_ message: String) {
        moveFeedState.applyFailure(message: message)
        refreshPresentedDestination()
    }

    mutating func applyCreatedFolder(_ folder: FeedManagementFolderSummary) {
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

    func moveFeedCommand() -> FeedManagementMoveFeedCommand? {
        moveFeedState.moveCommand()
    }

    func selectedMoveFeedFeed() -> FeedManagementFeedSummary? {
        moveFeedState.selectedFeed()
    }

    func derivedViewState() -> FeedManagementScreenViewState {
        FeedManagementScreenViewState(
            summary: summary,
            sections: sections,
            presentedDestination: presentedDestination
        )
    }

    func destinationPresentation(
        for scenarioID: FeedManagementScenarioID
    ) -> FeedManagementScreenDestinationPresentation {
        switch scenarioID {
        case .addFeed:
            return .addFeed(addFeedState.derivedPresentation())
        case .createFolder:
            return .createFolder(createFolderState.derivedPresentation())
        case .moveFeed:
            return .moveFeed(moveFeedState.derivedPresentation())
        }
    }

    private mutating func refreshPresentedDestination() {
        guard let presentedDestination else { return }
        presentScenario(presentedDestination.id)
    }
}
