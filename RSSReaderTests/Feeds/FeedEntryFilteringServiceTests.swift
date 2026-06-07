import Foundation
import Testing
@testable import RSSReader

@Suite("Feeds / Entry Filtering")
struct FeedEntryFilteringServiceTests {
    @Test
    func rejectionReasonsCoverMissingExternalIDReadablePayloadAndUsefulReference() {
        let entry = ParsedFeedEntryDTO(
            guid: nil,
            url: "not a url",
            canonicalURL: nil,
            title: "   ",
            summary: nil,
            contentHTML: nil,
            contentText: nil
        )

        let reasons = FeedEntryFilteringService.rejectionReasons(for: entry)

        #expect(reasons == [
            FeedEntryRejectionReason.missingExternalID,
            .missingReadablePayload,
            .missingUsefulReference
        ])
        #expect(FeedEntryFilteringService.isValid(entry) == false)
    }

    @Test
    func filteringKeepsValidEntriesInOriginalOrderAndRecordsRejectedEntries() throws {
        let firstValidEntry = makeEntry(
            externalID: "valid-1",
            guid: "guid-1",
            title: "First valid entry"
        )
        let rejectedEntry = ParsedFeedEntryDTO(
            externalID: "rejected-1",
            title: "Rejected entry without useful reference"
        )
        let secondValidEntry = makeEntry(
            externalID: "valid-2",
            canonicalURL: "https://example.com/articles/2",
            summary: "Second summary"
        )

        let result = FeedEntryFilteringService.filterEntries([
            firstValidEntry,
            rejectedEntry,
            secondValidEntry
        ])

        #expect(result.validEntries.map(\.externalID) == ["valid-1", "valid-2"])
        #expect(result.rejectedEntries.count == 1)

        let rejectedDiagnostic = try #require(result.rejectedEntries.first)
        #expect(rejectedDiagnostic.entry.externalID == "rejected-1")
        #expect(rejectedDiagnostic.entry.title == "Rejected entry without useful reference")
        #expect(rejectedDiagnostic.reasons == [FeedEntryRejectionReason.missingUsefulReference])
    }

    @Test
    func filterEntriesFromFeedReturnsRejectedDiagnosticsWithoutChangingMetadata() throws {
        let feed = ParsedFeedDTO(
            kind: .rss,
            metadata: ParsedFeedMetadataDTO(
                title: "Example Feed",
                siteURL: "https://example.com/"
            ),
            entries: [
                makeEntry(
                    externalID: "valid",
                    url: "https://example.com/articles/valid",
                    contentText: "Readable content"
                ),
                ParsedFeedEntryDTO(
                    externalID: nil,
                    guid: nil,
                    url: nil,
                    canonicalURL: nil,
                    title: nil,
                    summary: nil,
                    contentHTML: nil,
                    contentText: nil
                )
            ]
        )

        let result = FeedEntryFilteringService.filterEntries(from: feed)
        let filteredFeed = FeedEntryFilteringService.filterValidEntries(from: feed)

        #expect(result.validEntries.map(\.externalID) == ["valid"])
        #expect(filteredFeed.kind == .rss)
        #expect(filteredFeed.metadata.title == "Example Feed")
        #expect(filteredFeed.metadata.siteURL == "https://example.com/")
        #expect(filteredFeed.entries.map(\.externalID) == ["valid"])

        let rejectedDiagnostic = try #require(result.rejectedEntries.first)
        #expect(rejectedDiagnostic.entry.externalID == nil)
        #expect(rejectedDiagnostic.reasons == [
            FeedEntryRejectionReason.missingExternalID,
            .missingReadablePayload,
            .missingUsefulReference
        ])
    }

    private func makeEntry(
        externalID: String,
        guid: String? = nil,
        url: String? = nil,
        canonicalURL: String? = nil,
        title: String? = nil,
        summary: String? = nil,
        contentHTML: String? = nil,
        contentText: String? = nil
    ) -> ParsedFeedEntryDTO {
        ParsedFeedEntryDTO(
            externalID: externalID,
            guid: guid,
            url: url,
            canonicalURL: canonicalURL,
            title: title,
            summary: summary,
            contentHTML: contentHTML,
            contentText: contentText
        )
    }
}
