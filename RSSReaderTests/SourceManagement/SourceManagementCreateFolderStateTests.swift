import Foundation
import Testing
@testable import RSSReader

@Suite("Source Management / Create Folder State")
@MainActor
struct SourceManagementCreateFolderStateTests {
    @Test
    func createFolderStateValidatesDuplicateNamesAndBuildsPresentation() {
        var state = SourceManagementCreateFolderState()

        state.applyAvailableFolders(
            [
                SourceManagementFolderSummary(
                    id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                    name: "News",
                    sortOrder: 0,
                    feedCount: 3
                )
            ],
            isServiceAvailable: true
        )

        state.updateNameInput(" news ")
        #expect(state.validationMessage() == SourceManagementLocalization.duplicateFolderNameValidation)

        state.updateNameInput("Research")
        let presentation = state.derivedPresentation()
        #expect(presentation.validationMessage == nil)
        #expect(presentation.isPrimaryActionEnabled)
        #expect(presentation.placementDescription == SourceManagementLocalization.existingFolderPlacementDescription(count: 1))
    }
}
