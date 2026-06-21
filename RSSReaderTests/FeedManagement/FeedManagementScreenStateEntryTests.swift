import Foundation
import Testing
@testable import RSSReader

@Suite("Feed Management / Screen State / Entry")
@MainActor
struct FeedManagementScreenStateEntryTests {
    @Test
    func feedManagementScreenStateBuildsSeparatedEntrySections() {
        let state = FeedManagementScreenState.makePreviewFixture()
        let viewState = state.derivedViewState()

        #expect(viewState.summary.title == FeedManagementLocalization.summaryTitle)
        #expect(viewState.sections.map(\.id) == [.startNew, .organizeExisting])
        #expect(viewState.sections.first?.items.map(\.id) == [.addFeed, .createFolder])
        #expect(viewState.sections.last?.items.map(\.id) == [.moveFeed])
    }
}
