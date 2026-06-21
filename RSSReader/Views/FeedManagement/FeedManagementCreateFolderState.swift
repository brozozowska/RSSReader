import Foundation

struct FeedManagementCreateFolderState {
    private(set) var nameInput = ""
    private(set) var existingFolders: [FeedManagementFolderSummary] = []
    private(set) var isServiceAvailable = true
    private(set) var isSubmitting = false
    fileprivate(set) var feedback: FeedManagementCreateFolderFeedbackPresentation? = nil
    private(set) var editingFolder: FeedManagementFolderSummary? = nil

    var isEditing: Bool {
        editingFolder != nil
    }

    var editingName: String? {
        editingFolder?.name
    }

    mutating func applyAvailableFolders(
        _ folders: [FeedManagementFolderSummary],
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

    mutating func applyEditingFolder(_ folder: FeedManagementFolderSummary) {
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
        feedback = FeedManagementCreateFolderFeedbackPresentation(
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

    mutating func beginUpdate() -> FeedManagementUpdateFolderCommand? {
        guard let editingFolder, validationMessage() == nil else { return nil }
        isSubmitting = true
        feedback = nil
        return FeedManagementUpdateFolderCommand(
            folderID: editingFolder.id,
            name: normalizedName()
        )
    }

    mutating func applyCreatedFolder(_ folder: FeedManagementFolderSummary) {
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
        feedback = FeedManagementCreateFolderFeedbackPresentation(
            kind: .success,
            title: wasEditing
                ? FeedManagementLocalization.folderUpdatedTitle
                : FeedManagementLocalization.folderCreatedTitle,
            detail: wasEditing
                ? FeedManagementLocalization.folderRenamedDetail(folder.name)
                : FeedManagementLocalization.folderCreatedDetail(folder.name)
        )
    }

    mutating func applySubmissionFailure(message: String) {
        isSubmitting = false
        feedback = FeedManagementCreateFolderFeedbackPresentation(
            kind: .failure,
            title: isEditing
                ? FeedManagementLocalization.folderUpdateFailedTitle
                : FeedManagementLocalization.folderCreateFailedTitle,
            detail: message
        )
    }

    func derivedPresentation() -> FeedManagementCreateFolderPresentation {
        let validationMessage = validationMessage()
        let existingFolderPresentations = existingFolders.map { folder in
            FeedManagementCreateFolderExistingFolderPresentation(
                id: folder.id,
                name: folder.name,
                sortOrder: folder.sortOrder,
                feedCount: folder.feedCount
            )
        }

        return FeedManagementCreateFolderPresentation(
            title: isEditing
                ? FeedManagementLocalization.editFolderTitle
                : FeedManagementLocalization.createFolderTitle,
            summaryTitle: isEditing
                ? FeedManagementLocalization.folderNameSummaryTitle
                : FeedManagementLocalization.newFolderSummaryTitle,
            summaryDescription: isEditing
                ? FeedManagementLocalization.editFolderDescription
                : FeedManagementLocalization.newFolderDescription,
            nameInput: nameInput,
            namePrompt: FeedManagementLocalization.folderNamePrompt,
            validationMessage: validationMessage,
            existingFolders: existingFolderPresentations,
            emptyStateTitle: existingFolders.isEmpty ? FeedManagementLocalization.noFoldersTitle : nil,
            emptyStateDescription: existingFolders.isEmpty
                ? FeedManagementLocalization.noFoldersDescription
                : nil,
            placementDescription: placementDescription(for: nextSortOrder()),
            primaryActionTitle: isSubmitting
                ? (isEditing
                    ? FeedManagementLocalization.savingFolderAction
                    : FeedManagementLocalization.creatingFolderAction)
                : (isEditing
                    ? FeedManagementLocalization.saveFolderAction
                    : FeedManagementLocalization.createFolderTitle),
            isPrimaryActionEnabled: isServiceAvailable && validationMessage == nil && isSubmitting == false,
            isSubmitting: isSubmitting,
            feedback: feedback
        )
    }

    func validationMessage() -> String? {
        guard isServiceAvailable else {
            return FeedManagementLocalization.folderCreationUnavailableValidation
        }

        let normalizedValue = normalizedName()
        guard normalizedValue.isEmpty == false else {
            return FeedManagementLocalization.enterFolderNameValidation
        }

        if existingFolders.contains(where: { folder in
            folder.id != editingFolder?.id
                && folder.name.compare(normalizedValue, options: [.caseInsensitive]) == .orderedSame
        }) {
            return FeedManagementLocalization.duplicateFolderNameValidation
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

    private func placementDescription(for _: Int) -> String {
        if let editingFolder {
            return FeedManagementLocalization.editingFolderPlacementDescription(name: editingFolder.name)
        }

        if existingFolders.isEmpty {
            return FeedManagementLocalization.firstFolderPlacementDescription
        }

        return FeedManagementLocalization.existingFolderPlacementDescription(count: existingFolders.count)
    }
}
