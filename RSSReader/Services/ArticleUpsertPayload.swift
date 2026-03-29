import Foundation

struct ArticleUpsertPayload: Sendable {
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
    let isDeletedAtSource: Bool
    let fetchedAt: Date

    init?(
        entry: ParsedFeedEntryDTO,
        fetchedAt: Date = .now,
        isDeletedAtSource: Bool = false
    ) {
        guard
            let externalID = entry.externalID,
            let url = entry.url,
            let title = entry.title ?? entry.summary
        else {
            return nil
        }

        self.externalID = externalID
        self.guid = entry.guid
        self.url = url
        self.canonicalURL = entry.canonicalURL
        self.title = title
        self.summary = entry.summary
        self.contentHTML = entry.contentHTML
        self.contentText = entry.contentText
        self.author = entry.author
        self.publishedAt = FeedNormalizationService.parsePublishedAt(for: entry)
        self.updatedAtSource = FeedNormalizationService.parseUpdatedAt(for: entry)
        self.imageURL = entry.imageURL
        self.isDeletedAtSource = isDeletedAtSource
        self.fetchedAt = fetchedAt
    }
}
