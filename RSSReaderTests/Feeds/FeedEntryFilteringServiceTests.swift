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

    @Test
    func acceptedCanonicalGUIDAndContentEntriesAllProducePersistablePayloads() throws {
        let canonicalEntry = makeEntry(
            externalID: "canonical-entry",
            canonicalURL: "https://example.com/articles/canonical",
            summary: "Canonical summary"
        )
        let guidContentEntry = makeEntry(
            externalID: "guid-content-entry",
            guid: "guid-content",
            contentHTML: "<p>GUID content</p>"
        )
        let urlContentEntry = makeEntry(
            externalID: "url-content-entry",
            url: "https://example.com/articles/content-only",
            contentText: "URL content"
        )
        let referenceFreeContentEntry = makeEntry(
            externalID: "reference-free-content-entry",
            contentText: "Readable but not addressable"
        )

        let result = FeedEntryFilteringService.filterEntries([
            canonicalEntry,
            guidContentEntry,
            urlContentEntry,
            referenceFreeContentEntry
        ])
        let payloads = try ArticleUpsertPayload.makeAll(
            entries: result.validEntries,
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        #expect(result.validEntries.map(\.externalID) == [
            "canonical-entry",
            "guid-content-entry",
            "url-content-entry"
        ])
        #expect(payloads.map(\.externalID) == [
            "canonical-entry",
            "guid-content-entry",
            "url-content-entry"
        ])
        #expect(payloads[0].url == "https://example.com/articles/canonical")
        #expect(payloads[0].title == "Canonical summary")
        #expect(payloads[1].url.isEmpty)
        #expect(payloads[1].title.isEmpty)
        #expect(payloads[1].contentHTML == "<p>GUID content</p>")
        #expect(payloads[2].url == "https://example.com/articles/content-only")
        #expect(payloads[2].title.isEmpty)

        let rejectedDiagnostic = try #require(result.rejectedEntries.first)
        #expect(rejectedDiagnostic.entry.externalID == "reference-free-content-entry")
        #expect(rejectedDiagnostic.reasons == [.missingUsefulReference])
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
