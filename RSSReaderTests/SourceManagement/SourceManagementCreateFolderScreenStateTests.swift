import Foundation
import Testing
@testable import RSSReader

@Suite("Source Management / Screen State / Create Folder")
@MainActor
struct SourceManagementCreateFolderScreenStateTests {
    @Test
    func sourceManagementScreenStateBuildsCreateFolderPresentationWithValidationAndPlacement() {
        var state = SourceManagementScreenState.makePreviewFixture()
        state.applyCreateFolderContext(
            folders: [
                SourceManagementFolderSummary(
                    id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                    name: "News",
                    sortOrder: 0,
                    feedCount: 5
                ),
                SourceManagementFolderSummary(
                    id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
                    name: "Tech",
                    sortOrder: 1,
                    feedCount: 3
                )
            ]
        )
        state.presentScenario(.createFolder)

        guard case .createFolder(let initialDestination)? = state.derivedViewState().presentedDestination else {
            Issue.record("Expected create-folder destination presentation")
            return
        }

        #expect(initialDestination.existingFolders.map(\.name) == ["News", "Tech"])
        #expect(initialDestination.placementDescription == SourceManagementLocalization.existingFolderPlacementDescription(count: 2))
        #expect(initialDestination.isPrimaryActionEnabled == false)

        state.updateCreateFolderNameInput("News")

        guard case .createFolder(let duplicateDestination)? = state.derivedViewState().presentedDestination else {
            Issue.record("Expected create-folder destination presentation after duplicate input")
            return
        }

        #expect(duplicateDestination.validationMessage == SourceManagementLocalization.duplicateFolderNameValidation)
        #expect(duplicateDestination.isPrimaryActionEnabled == false)

        state.updateCreateFolderNameInput(" tEcH ")

        guard case .createFolder(let caseDuplicateDestination)? = state.derivedViewState().presentedDestination else {
            Issue.record("Expected create-folder destination presentation after case-insensitive duplicate input")
            return
        }

        #expect(caseDuplicateDestination.validationMessage == SourceManagementLocalization.duplicateFolderNameValidation)
        #expect(caseDuplicateDestination.isPrimaryActionEnabled == false)

        state.updateCreateFolderNameInput("Research")

        guard case .createFolder(let validDestination)? = state.derivedViewState().presentedDestination else {
            Issue.record("Expected create-folder destination presentation after valid input")
            return
        }

        #expect(validDestination.validationMessage == nil)
        #expect(validDestination.isPrimaryActionEnabled)
    }
}
