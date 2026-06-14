import Foundation

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
            title: wasEditing
                ? SourceManagementLocalization.folderUpdatedTitle
                : SourceManagementLocalization.folderCreatedTitle,
            detail: wasEditing
                ? SourceManagementLocalization.folderRenamedDetail(folder.name)
                : SourceManagementLocalization.folderCreatedDetail(folder.name)
        )
    }

    mutating func applySubmissionFailure(message: String) {
        isSubmitting = false
        feedback = SourceManagementCreateFolderFeedbackPresentation(
            kind: .failure,
            title: isEditing
                ? SourceManagementLocalization.folderUpdateFailedTitle
                : SourceManagementLocalization.folderCreateFailedTitle,
            detail: message
        )
    }

    func derivedPresentation() -> SourceManagementCreateFolderPresentation {
        let validationMessage = validationMessage()
        let existingFolderPresentations = existingFolders.map { folder in
            SourceManagementCreateFolderExistingFolderPresentation(
                id: folder.id,
                name: folder.name,
                sortOrder: folder.sortOrder,
                feedCount: folder.feedCount
            )
        }

        return SourceManagementCreateFolderPresentation(
            title: isEditing
                ? SourceManagementLocalization.editFolderTitle
                : SourceManagementLocalization.createFolderTitle,
            summaryTitle: isEditing
                ? SourceManagementLocalization.folderNameSummaryTitle
                : SourceManagementLocalization.newFolderSummaryTitle,
            summaryDescription: isEditing
                ? SourceManagementLocalization.editFolderDescription
                : SourceManagementLocalization.newFolderDescription,
            nameInput: nameInput,
            namePrompt: SourceManagementLocalization.folderNamePrompt,
            validationMessage: validationMessage,
            existingFolders: existingFolderPresentations,
            emptyStateTitle: existingFolders.isEmpty ? SourceManagementLocalization.noFoldersTitle : nil,
            emptyStateDescription: existingFolders.isEmpty
                ? SourceManagementLocalization.noFoldersDescription
                : nil,
            placementDescription: placementDescription(for: nextSortOrder()),
            primaryActionTitle: isSubmitting
                ? (isEditing
                    ? SourceManagementLocalization.savingFolderAction
                    : SourceManagementLocalization.creatingFolderAction)
                : (isEditing
                    ? SourceManagementLocalization.saveFolderAction
                    : SourceManagementLocalization.createFolderTitle),
            isPrimaryActionEnabled: isServiceAvailable && validationMessage == nil && isSubmitting == false,
            isSubmitting: isSubmitting,
            feedback: feedback
        )
    }

    func validationMessage() -> String? {
        guard isServiceAvailable else {
            return SourceManagementLocalization.folderCreationUnavailableValidation
        }

        let normalizedValue = normalizedName()
        guard normalizedValue.isEmpty == false else {
            return SourceManagementLocalization.enterFolderNameValidation
        }

        if existingFolders.contains(where: { folder in
            folder.id != editingFolder?.id
                && folder.name.compare(normalizedValue, options: [.caseInsensitive]) == .orderedSame
        }) {
            return SourceManagementLocalization.duplicateFolderNameValidation
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
            return SourceManagementLocalization.editingFolderPlacementDescription(name: editingFolder.name)
        }

        if existingFolders.isEmpty {
            return SourceManagementLocalization.firstFolderPlacementDescription
        }

        return SourceManagementLocalization.existingFolderPlacementDescription(count: existingFolders.count)
    }
}
