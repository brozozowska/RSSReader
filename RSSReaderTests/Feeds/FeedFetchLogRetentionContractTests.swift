import Foundation
import Testing
@testable import RSSReader

@Suite("Feeds / Feed Fetch Log Retention Contract")
struct FeedFetchLogRetentionContractTests {
    @Test
    func currentContractKeepsOneWeekAndTwoHundredLogsPerFeed() {
        let contract = FeedFetchLogRetentionContract.current
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        #expect(contract.maximumAge == 7 * 24 * 60 * 60)
        #expect(contract.maximumLogCountPerFeed == 200)
        #expect(contract.cutoffDate(now: now) == now.addingTimeInterval(-(7 * 24 * 60 * 60)))
    }
}
