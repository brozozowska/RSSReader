import Foundation
import Testing
@testable import RSSReader

@Suite("Feed Management / Create Folder State")
@MainActor
struct FeedManagementCreateFolderStateTests {
    @Test
    func createFolderStateValidatesDuplicateNamesAndBuildsPresentation() {
        var state = FeedManagementCreateFolderState()

        state.applyAvailableFolders(
            [
                FeedManagementFolderSummary(
                    id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                    name: "News",
                    sortOrder: 0,
                    feedCount: 3
                )
            ],
            isServiceAvailable: true
        )

        state.updateNameInput(" news ")
        #expect(state.validationMessage() == FeedManagementLocalization.duplicateFolderNameValidation)

        state.updateNameInput("Research")
        let presentation = state.derivedPresentation()
        #expect(presentation.validationMessage == nil)
        #expect(presentation.isPrimaryActionEnabled)
        #expect(presentation.placementDescription == FeedManagementLocalization.existingFolderPlacementDescription(count: 1))
    }
}
