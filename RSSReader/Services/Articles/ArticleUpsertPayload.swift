import Foundation

typealias ArticleUpsertPayloadMaterializationProbe = @Sendable (Int, ArticleUpsertPayload) -> Void

nonisolated enum ArticleUpsertPayloadConstructionError: Error, Equatable {
    case nonPersistableEntry(index: Int)
}

nonisolated struct ArticleUpsertPayload: Sendable {
    let externalID: String
    let guid: String?
    let url: String
    let canonicalURL: String?
    let title: String
    let summary: String?
    let contentHTML: String?
    let contentText: String?
    let searchableText: String
    let author: String?
    let publishedAt: Date?
    let updatedAtSource: Date?
    let imageURL: String?
    let fetchedAt: Date

    private init?(
        preparedEntry entry: ParsedFeedEntryDTO,
        fetchedAt: Date
    ) {
        guard let externalID = Self.firstNonEmptyValue(entry.externalID) else {
            return nil
        }

        self.externalID = externalID
        self.guid = entry.guid
        self.url = Self.firstNonEmptyValue(entry.url, entry.canonicalURL) ?? ""
        self.canonicalURL = entry.canonicalURL
        self.title = Self.firstNonEmptyValue(entry.title, entry.summary) ?? ""
        self.summary = entry.summary
        self.contentHTML = entry.contentHTML
        self.contentText = entry.contentText
        self.searchableText = ArticleSearchableTextPolicy.materialize(
            title: self.title,
            summary: entry.summary,
            contentHTML: entry.contentHTML,
            contentText: entry.contentText,
            author: entry.author
        )
        self.author = entry.author
        self.publishedAt = entry.publishedAt
        self.updatedAtSource = entry.updatedAt
        self.imageURL = entry.imageURL
        self.fetchedAt = fetchedAt
    }

    static func makeAllPrepared(
        entries: [ParsedFeedEntryDTO],
        fetchedAt: Date,
        cancellationCheck: FeedParsingCancellationCheck = { try Task.checkCancellation() },
        materializationProbe: ArticleUpsertPayloadMaterializationProbe? = nil
    ) throws -> [ArticleUpsertPayload] {
        var payloads: [ArticleUpsertPayload] = []
        payloads.reserveCapacity(entries.count)

        for (index, entry) in entries.enumerated() {
            try FeedParsingCancellationPolicy.checkBeforeEntry(
                at: index,
                cancellationCheck: cancellationCheck
            )
            guard let payload = ArticleUpsertPayload(
                preparedEntry: entry,
                fetchedAt: fetchedAt
            ) else {
                throw ArticleUpsertPayloadConstructionError.nonPersistableEntry(index: index)
            }
            payloads.append(payload)
            materializationProbe?(index + 1, payload)
        }
        try cancellationCheck()
        return payloads
    }

    static func hasPersistableExternalID(_ entry: ParsedFeedEntryDTO) -> Bool {
        firstNonEmptyValue(entry.externalID) != nil
    }

    private static func firstNonEmptyValue(_ values: String?...) -> String? {
        for value in values {
            guard let value else { continue }
            guard value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                continue
            }
            return value
        }
        return nil
    }
}
