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
            title: wasEditing ? "Folder updated" : "Folder created",
            detail: wasEditing
                ? "\"\(folder.name)\" has been renamed."
                : "\"\(folder.name)\" is ready for sources."
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
            summaryTitle: isEditing ? "Folder Name" : "New Folder",
            summaryDescription: isEditing
                ? "Rename this folder. Sources inside it stay in the same place."
                : "Create a folder for sources you want to keep together.",
            nameInput: nameInput,
            namePrompt: "Folder Name",
            validationMessage: validationMessage,
            existingFolders: existingFolderPresentations,
            emptyStateTitle: existingFolders.isEmpty ? "No folders yet" : nil,
            emptyStateDescription: existingFolders.isEmpty
                ? "Create the first folder, then add or move sources into it."
                : nil,
            placementDescription: placementDescription(for: nextSortOrder()),
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
            return "Folder creation is unavailable right now."
        }

        let normalizedValue = normalizedName()
        guard normalizedValue.isEmpty == false else {
            return "Enter a folder name to continue."
        }

        if existingFolders.contains(where: { folder in
            folder.id != editingFolder?.id
                && folder.name.compare(normalizedValue, options: [.caseInsensitive]) == .orderedSame
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

    private func placementDescription(for _: Int) -> String {
        if let editingFolder {
            return "\"\(editingFolder.name)\" keeps its current order."
        }

        if existingFolders.isEmpty {
            return "This will be the first folder."
        }

        return "This folder will be added after \(existingFolders.count) existing folders."
    }
}
