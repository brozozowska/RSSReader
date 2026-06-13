import Foundation
import Testing
@testable import RSSReader

@Suite("Source Management / Screen State / Entry")
@MainActor
struct SourceManagementScreenStateEntryTests {
    @Test
    func sourceManagementScreenStateBuildsSeparatedEntrySections() {
        let state = SourceManagementScreenState.makePreviewFixture()
        let viewState = state.derivedViewState()

        #expect(viewState.summary.title == "Manage sources and folders")
        #expect(viewState.sections.map(\.id) == [.startNew, .organizeExisting])
        #expect(viewState.sections.first?.items.map(\.id) == [.addFeed, .createFolder])
        #expect(viewState.sections.last?.items.map(\.id) == [.moveSource])
    }
}
