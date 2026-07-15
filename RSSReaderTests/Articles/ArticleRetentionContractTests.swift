import Foundation
import Testing
@testable import RSSReader

@Suite("Articles / Retention Contract")
struct ArticleRetentionContractTests {
    private let contract = ArticleRetentionContract.current

    @Test
    func contractCapsCombinedUnstarredArticleCountPerFeedAndExemptsStarredArticles() {
        #expect(contract.maximumUnstarredArticleCountPerFeed == 2_000)
        #expect(contract.starredArticlesAreExemptFromAutomaticRetention)
    }

    @Test
    func contractMapsEveryPersistedPolicyToExplicitTimeRule() {
        #expect(contract.timeRule(for: .currentFeedOnly) == .whileReturnedByFeed)
        #expect(contract.timeRule(for: .twoDays) == .sourceAge(maximumAge: 2 * 24 * 60 * 60))
        #expect(contract.timeRule(for: .oneWeek) == .sourceAge(maximumAge: 7 * 24 * 60 * 60))
        #expect(contract.timeRule(for: .twoWeeks) == .sourceAge(maximumAge: 14 * 24 * 60 * 60))
        #expect(contract.timeRule(for: .oneMonth) == .sourceAge(maximumAge: 30 * 24 * 60 * 60))
    }

    @Test
    func sourceAgeUsesPublishedDateBeforeUpdatedDateAndDoesNotDependOnArchiveDate() {
        let publishedAt = Date(timeIntervalSince1970: 100)
        let updatedAtSource = Date(timeIntervalSince1970: 200)
        let firstMaterializedAt = Date(timeIntervalSince1970: 300)

        let referenceDate = contract.sourceAgeReferenceDate(
            publishedAt: publishedAt,
            updatedAtSource: updatedAtSource,
            firstMaterializedAt: firstMaterializedAt
        )

        #expect(referenceDate == publishedAt)
    }

    @Test
    func sourceAgeUsesUpdatedDateWhenPublishedDateIsMissing() {
        let updatedAtSource = Date(timeIntervalSince1970: 200)

        let referenceDate = contract.sourceAgeReferenceDate(
            publishedAt: nil,
            updatedAtSource: updatedAtSource,
            firstMaterializedAt: Date(timeIntervalSince1970: 300)
        )

        #expect(referenceDate == updatedAtSource)
    }

    @Test
    func futureSourceDateIsClampedToFirstMaterializationDate() {
        let firstMaterializedAt = Date(timeIntervalSince1970: 300)

        let referenceDate = contract.sourceAgeReferenceDate(
            publishedAt: Date(timeIntervalSince1970: 400),
            updatedAtSource: nil,
            firstMaterializedAt: firstMaterializedAt
        )

        #expect(referenceDate == firstMaterializedAt)
    }

    @Test
    func missingSourceDateUsesOnlyCountBudgetAndStableMaterializationOrdering() {
        let firstMaterializedAt = Date(timeIntervalSince1970: 300)

        #expect(
            contract.sourceAgeReferenceDate(
                publishedAt: nil,
                updatedAtSource: nil,
                firstMaterializedAt: firstMaterializedAt
            ) == nil
        )
        #expect(
            contract.countOrderingDate(
                publishedAt: nil,
                updatedAtSource: nil,
                firstMaterializedAt: firstMaterializedAt
            ) == firstMaterializedAt
        )
    }

    @Test
    func sourceAgeCutoffExistsOnlyForTimeBasedPolicies() {
        let now = Date(timeIntervalSince1970: 1_000_000)

        #expect(contract.sourceAgeCutoffDate(for: .currentFeedOnly, now: now) == nil)
        #expect(
            contract.sourceAgeCutoffDate(for: .oneWeek, now: now)
                == now.addingTimeInterval(-(7 * 24 * 60 * 60))
        )
    }
}
