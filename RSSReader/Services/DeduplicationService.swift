import Foundation

enum DeduplicationService {
    static func deduplicate(_ feed: ParsedFeedDTO) -> ParsedFeedDTO {
        ParsedFeedDTO(
            kind: feed.kind,
            metadata: feed.metadata,
            entries: deduplicate(feed.entries)
        )
    }

    static func deduplicate(_ entries: [ParsedFeedEntryDTO]) -> [ParsedFeedEntryDTO] {
        var mergedEntriesByKey: [String: ParsedFeedEntryDTO] = [:]
        var orderedKeys: [String] = []
        var uniqueEntriesWithoutKey: [ParsedFeedEntryDTO] = []

        for entry in entries {
            guard let key = deduplicationKey(for: entry) else {
                uniqueEntriesWithoutKey.append(entry)
                continue
            }

            if let existingEntry = mergedEntriesByKey[key] {
                mergedEntriesByKey[key] = merge(existingEntry, with: entry)
            } else {
                mergedEntriesByKey[key] = entry
                orderedKeys.append(key)
            }
        }

        let mergedEntries = orderedKeys.compactMap { mergedEntriesByKey[$0] }
        return mergedEntries + uniqueEntriesWithoutKey
    }

    private static func deduplicationKey(for entry: ParsedFeedEntryDTO) -> String? {
        if let externalID = normalized(entry.externalID) {
            return "external-id|\(externalID)"
        }

        if let guid = normalized(entry.guid) {
            return "guid|\(guid)"
        }

        if let canonicalURL = normalized(entry.canonicalURL) {
            return "canonical-url|\(canonicalURL)"
        }

        if let articleURL = normalized(entry.url) {
            return "article-url|\(articleURL)"
        }

        if let title = normalized(entry.title), let publishedAt = normalized(entry.publishedAtRaw) {
            return "title-date|\(title)|\(publishedAt)"
        }

        return nil
    }

    private static func merge(_ lhs: ParsedFeedEntryDTO, with rhs: ParsedFeedEntryDTO) -> ParsedFeedEntryDTO {
        ParsedFeedEntryDTO(
            externalID: preferredValue(lhs.externalID, rhs.externalID),
            guid: preferredValue(lhs.guid, rhs.guid),
            url: preferredValue(lhs.url, rhs.url),
            canonicalURL: preferredValue(lhs.canonicalURL, rhs.canonicalURL),
            title: preferredValue(lhs.title, rhs.title),
            summary: preferredValue(lhs.summary, rhs.summary),
            contentHTML: preferredValue(lhs.contentHTML, rhs.contentHTML),
            contentText: preferredValue(lhs.contentText, rhs.contentText),
            author: preferredValue(lhs.author, rhs.author),
            publishedAtRaw: preferredValue(lhs.publishedAtRaw, rhs.publishedAtRaw),
            updatedAtRaw: preferredValue(lhs.updatedAtRaw, rhs.updatedAtRaw),
            imageURL: preferredValue(lhs.imageURL, rhs.imageURL)
        )
    }

    private static func preferredValue(_ lhs: String?, _ rhs: String?) -> String? {
        let left = normalized(lhs)
        let right = normalized(rhs)

        switch (left, right) {
        case (.none, .none):
            return nil
        case let (.some(value), .none), let (.none, .some(value)):
            return value
        case let (.some(leftValue), .some(rightValue)):
            return score(rightValue) > score(leftValue) ? rightValue : leftValue
        }
    }

    private static func score(_ value: String) -> Int {
        value.count
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedValue.isEmpty ? nil : normalizedValue
    }
}
