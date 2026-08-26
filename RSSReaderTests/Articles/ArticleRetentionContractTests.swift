import Foundation
import Testing
@testable import RSSReader

@Suite("Articles / Retention Contract")
struct ArticleRetentionContractTests {
    private let contract = ArticleRetentionContract.current

    @Test
    func contractCapsArchivedUnstarredArticleCountPerFeedAndExemptsStarredArticles() {
        #expect(contract.maximumArchivedUnstarredArticleCountPerFeed == 2_000)
        #expect(contract.starredArticlesAreExemptFromAutomaticRetention)
    }

    @Test
    func contractMapsEveryPersistedPolicyToExplicitTimeRule() {
        #expect(contract.timeRule(for: .currentFeedOnly) == .removeOnFeedAbsence)
        #expect(contract.timeRule(for: .twoDays) == .archivedAge(maximumAge: 2 * 24 * 60 * 60))
        #expect(contract.timeRule(for: .oneWeek) == .archivedAge(maximumAge: 7 * 24 * 60 * 60))
        #expect(contract.timeRule(for: .twoWeeks) == .archivedAge(maximumAge: 14 * 24 * 60 * 60))
        #expect(contract.timeRule(for: .oneMonth) == .archivedAge(maximumAge: 30 * 24 * 60 * 60))
    }

    @Test
    func archiveCutoffExistsOnlyForTimeBasedPoliciesAndUsesExactBoundary() {
        let now = Date(timeIntervalSince1970: 1_000_000)

        #expect(contract.archiveCutoffDate(for: .currentFeedOnly, now: now) == nil)
        #expect(
            contract.archiveCutoffDate(for: .oneWeek, now: now)
                == now.addingTimeInterval(-(7 * 24 * 60 * 60))
        )
    }
}
