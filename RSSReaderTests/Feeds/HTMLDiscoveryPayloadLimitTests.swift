import Foundation
import Testing
@testable import RSSReader

@Suite("Feeds / HTML Discovery Payload Limits")
struct HTMLDiscoveryPayloadLimitTests {
    @Test
    func decoderRejectsOversizedHTMLBeforeStringMaterialization() throws {
        let budget = AppResourceBudgetContract.current.discoveryHTML.body
        let response = HTTPResponse(
            url: URL(string: "https://example.com/")!,
            statusCode: 200,
            headers: ["Content-Type": "text/html"],
            body: Data(repeating: 0x20, count: Int(budget.maximumCompressedBodyBytes + 1))
        )

        #expect(
            throws: AppResourceBudgetViolation.compressedBodySizeExceeded(
                input: .discoveryHTML,
                maximumBytes: budget.maximumCompressedBodyBytes,
                actualBytes: budget.maximumCompressedBodyBytes + 1
            )
        ) {
            try HTMLDiscoveryResponseDecoder.decode(response)
        }
    }

    @Test
    func decoderRejectsUnsupportedMIMEBeforeAttemptingTextDecode() throws {
        let response = HTTPResponse(
            url: URL(string: "https://example.com/")!,
            statusCode: 200,
            headers: ["content-type": "application/octet-stream"],
            body: Data([0xFF])
        )

        #expect(
            throws: AppResourceBudgetViolation.unsupportedMIMEType(
                input: .discoveryHTML,
                receivedMIMEType: "application/octet-stream"
            )
        ) {
            try HTMLDiscoveryResponseDecoder.decode(response)
        }
    }

    @Test
    func parserStopsBeforeLinkTagsBeyondInspectionLimit() throws {
        let budget = AppResourceBudgetContract.current.discoveryHTML
        let ignoredTags = (0..<budget.maximumLinkTagCountToInspect)
            .map { #"<link rel="stylesheet" href="/style-\#($0).css">"# }
            .joined()
        let html = ignoredTags
            + #"<link rel="alternate" type="application/rss+xml" href="/too-late.xml">"#

        let candidates = FeedManagementFeedDiscoveryPlanner.autodiscoveredFeedURLs(
            in: html,
            baseURL: URL(string: "https://example.com/")!
        )

        #expect(candidates.isEmpty)
    }

    @Test
    func feedAndIconBuildersCapUniqueDiscoveryCandidates() throws {
        let budget = AppResourceBudgetContract.current.discoveryHTML
        let html = (0..<(budget.maximumDiscoveryCandidateCount + 5))
            .map {
                #"<link rel="alternate icon" type="application/rss+xml" href="/candidate-\#($0).xml">"#
            }
            .joined()
        let baseURL = URL(string: "https://example.com/")!

        let feedCandidates = FeedManagementFeedDiscoveryPlanner.autodiscoveredFeedURLs(
            in: html,
            baseURL: baseURL
        )
        let iconCandidates = FeedIconCandidateBuilder.htmlIconCandidates(
            in: html,
            baseURL: baseURL
        )

        #expect(feedCandidates.count == budget.maximumDiscoveryCandidateCount)
        #expect(iconCandidates.count == budget.maximumDiscoveryCandidateCount)
        #expect(Set(feedCandidates.map(\.absoluteString)).count == feedCandidates.count)
        #expect(Set(iconCandidates.map(\.absoluteString)).count == iconCandidates.count)
    }
}
