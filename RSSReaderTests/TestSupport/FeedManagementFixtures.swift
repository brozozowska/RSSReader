import Foundation
@testable import RSSReader

extension FeedManagementScreenState {
    static func makePreviewFixture(
        presentedScenarioID: FeedManagementScenarioID? = nil
    ) -> FeedManagementScreenState {
        var state = FeedManagementScreenState()
        if let presentedScenarioID {
            state.presentScenario(presentedScenarioID)
        }
        return state
    }
}
