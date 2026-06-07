import Foundation
import Testing
@testable import RSSReader

@Suite("Articles / Deduplication Service")
struct DeduplicationServiceTests {
    @Test
    func deduplicatesBySupportedKeysAndKeepsFirstKeyOrder() {
        let entries = [
            makeEntry(externalID: "external-1", title: "External first"),
            makeEntry(guid: "guid-1", title: "Guid first"),
            makeEntry(canonicalURL: "https://example.com/canonical", title: "Canonical first"),
            makeEntry(url: "https://example.com/article", title: "Article URL first"),
            makeEntry(title: "Title Date first", publishedAtRaw: "Tue, 02 Jan 2024 10:00:00 +0000"),
            makeEntry(externalID: " external-1 ", title: "External richer duplicate"),
            makeEntry(guid: " guid-1 ", title: "Guid richer duplicate"),
            makeEntry(canonicalURL: " https://example.com/canonical ", title: "Canonical richer duplicate"),
            makeEntry(url: " https://example.com/article ", title: "Article URL richer duplicate"),
            makeEntry(title: " Title Date first ", summary: "Title-date duplicate", publishedAtRaw: " Tue, 02 Jan 2024 10:00:00 +0000 "),
            makeEntry(title: "No key entry")
        ]

        let deduplicatedEntries = DeduplicationService.deduplicate(entries)

        #expect(deduplicatedEntries.map { $0.title } == [
            "External richer duplicate",
            "Guid richer duplicate",
            "Canonical richer duplicate",
            "Article URL richer duplicate",
            "Title Date first",
            "No key entry"
        ])
    }

    @Test
    func entriesWithoutDeduplicationKeyRemainSeparateAndKeepRelativeOrder() {
        let entries = [
            makeEntry(title: "No key first"),
            makeEntry(title: "No key second"),
            makeEntry(summary: "No key third")
        ]

        let deduplicatedEntries = DeduplicationService.deduplicate(entries)

        #expect(deduplicatedEntries.map { $0.title } == [
            "No key first",
            "No key second",
            nil
        ])
        #expect(deduplicatedEntries.map { $0.summary } == [
            nil,
            nil,
            "No key third"
        ])
    }

    @Test
    func mergePrefersRicherIdentityTextURLMediaAndDatePayloads() throws {
        let baseEntry = makeEntry(
            externalID: "duplicate",
            guid: "g",
            url: "http://example.com/a?utm=feed#fragment",
            canonicalURL: "not a canonical url",
            title: "https://example.com/title",
            summary: "short",
            contentHTML: "plain body",
            contentText: "short text",
            author: "author@example.com",
            publishedAtRaw: "Wed, 03 Jan 2024 10:00:00 +0000",
            updatedAtRaw: "Wed, 03 Jan 2024 10:00:00 +0000",
            imageURL: "http://example.com/images/thumb.jpg?utm=feed"
        )
        let richerDuplicate = makeEntry(
            externalID: "duplicate",
            guid: "longer-guid",
            url: "https://example.com/articles/full",
            canonicalURL: "https://example.com/a",
            title: "Readable Article Title",
            summary: "Longer readable summary\nwith details",
            contentHTML: "<article><p>Full HTML body</p></article>",
            contentText: "Longer readable text payload",
            author: "Readable Author",
            publishedAtRaw: "Tue, 02 Jan 2024 10:00:00 +0000",
            updatedAtRaw: "Thu, 04 Jan 2024 10:00:00 +0000",
            imageURL: "https://example.com/images/hero.jpg"
        )

        let deduplicatedEntries = DeduplicationService.deduplicate([baseEntry, richerDuplicate])
        let mergedEntry = try #require(deduplicatedEntries.first)

        #expect(deduplicatedEntries.count == 1)
        #expect(mergedEntry.externalID == "duplicate")
        #expect(mergedEntry.guid == "longer-guid")
        #expect(mergedEntry.url == "https://example.com/articles/full")
        #expect(mergedEntry.canonicalURL == "https://example.com/a")
        #expect(mergedEntry.title == "Readable Article Title")
        #expect(mergedEntry.summary == "Longer readable summary\nwith details")
        #expect(mergedEntry.contentHTML == "<article><p>Full HTML body</p></article>")
        #expect(mergedEntry.contentText == "Longer readable text payload")
        #expect(mergedEntry.author == "Readable Author")
        #expect(mergedEntry.publishedAtRaw == "Tue, 02 Jan 2024 10:00:00 +0000")
        #expect(mergedEntry.updatedAtRaw == "Thu, 04 Jan 2024 10:00:00 +0000")
        #expect(mergedEntry.imageURL == "https://example.com/images/hero.jpg")
    }

    @Test
    func deduplicatingFeedPreservesFeedMetadataAndKind() {
        let feed = ParsedFeedDTO(
            kind: .atom,
            metadata: ParsedFeedMetadataDTO(
                title: "Example Feed",
                siteURL: "https://example.com/"
            ),
            entries: [
                makeEntry(externalID: "duplicate", title: "First"),
                makeEntry(externalID: "duplicate", title: "Second richer title")
            ]
        )

        let deduplicatedFeed = DeduplicationService.deduplicate(feed)

        #expect(deduplicatedFeed.kind == .atom)
        #expect(deduplicatedFeed.metadata.title == "Example Feed")
        #expect(deduplicatedFeed.metadata.siteURL == "https://example.com/")
        #expect(deduplicatedFeed.entries.map { $0.title } == ["Second richer title"])
    }

    private func makeEntry(
        externalID: String? = nil,
        guid: String? = nil,
        url: String? = nil,
        canonicalURL: String? = nil,
        title: String? = nil,
        summary: String? = nil,
        contentHTML: String? = nil,
        contentText: String? = nil,
        author: String? = nil,
        publishedAtRaw: String? = nil,
        updatedAtRaw: String? = nil,
        imageURL: String? = nil
    ) -> ParsedFeedEntryDTO {
        ParsedFeedEntryDTO(
            externalID: externalID,
            guid: guid,
            url: url,
            canonicalURL: canonicalURL,
            title: title,
            summary: summary,
            contentHTML: contentHTML,
            contentText: contentText,
            author: author,
            publishedAtRaw: publishedAtRaw,
            updatedAtRaw: updatedAtRaw,
            imageURL: imageURL
        )
    }
}
