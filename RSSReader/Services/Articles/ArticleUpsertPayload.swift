import Foundation

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
    let author: String?
    let publishedAt: Date?
    let updatedAtSource: Date?
    let imageURL: String?
    let archivedAt: Date?
    let fetchedAt: Date

    init?(
        entry: ParsedFeedEntryDTO,
        fetchedAt: Date = .now,
        archivedAt: Date? = nil
    ) {
        self.init(
            preparedEntry: entry,
            publishedAt: FeedNormalizationService.parsePublishedAt(for: entry),
            updatedAtSource: FeedNormalizationService.parseUpdatedAt(for: entry),
            fetchedAt: fetchedAt,
            archivedAt: archivedAt
        )
    }

    private init?(
        preparedEntry entry: ParsedFeedEntryDTO,
        publishedAt: Date?,
        updatedAtSource: Date?,
        fetchedAt: Date,
        archivedAt: Date?
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
        self.author = entry.author
        self.publishedAt = publishedAt
        self.updatedAtSource = updatedAtSource
        self.imageURL = entry.imageURL
        self.archivedAt = archivedAt
        self.fetchedAt = fetchedAt
    }

    static func makeAll(
        entries: [ParsedFeedEntryDTO],
        fetchedAt: Date,
        archivedAt: Date? = nil
    ) throws -> [ArticleUpsertPayload] {
        try entries.enumerated().map { index, entry in
            guard let payload = ArticleUpsertPayload(
                entry: entry,
                fetchedAt: fetchedAt,
                archivedAt: archivedAt
            ) else {
                throw ArticleUpsertPayloadConstructionError.nonPersistableEntry(index: index)
            }
            return payload
        }
    }

    static func makeAllPrepared(
        entries: [ParsedFeedEntryDTO],
        fetchedAt: Date,
        archivedAt: Date? = nil
    ) throws -> [ArticleUpsertPayload] {
        try entries.enumerated().map { index, entry in
            guard let payload = ArticleUpsertPayload(
                preparedEntry: entry,
                publishedAt: entry.publishedAt,
                updatedAtSource: entry.updatedAt,
                fetchedAt: fetchedAt,
                archivedAt: archivedAt
            ) else {
                throw ArticleUpsertPayloadConstructionError.nonPersistableEntry(index: index)
            }
            return payload
        }
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
