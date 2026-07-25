import Foundation

nonisolated enum DeduplicationService {
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
        let publishedDate = preferredDate(
            lhsRawValue: lhs.publishedAtRaw,
            lhsParsedValue: lhs.publishedAt,
            rhsRawValue: rhs.publishedAtRaw,
            rhsParsedValue: rhs.publishedAt,
            strategy: .earliest
        )
        let updatedDate = preferredDate(
            lhsRawValue: lhs.updatedAtRaw,
            lhsParsedValue: lhs.updatedAt,
            rhsRawValue: rhs.updatedAtRaw,
            rhsParsedValue: rhs.updatedAt,
            strategy: .latest
        )

        return ParsedFeedEntryDTO(
            externalID: preferredIdentityValue(lhs.externalID, rhs.externalID),
            guid: preferredIdentityValue(lhs.guid, rhs.guid),
            url: preferredArticleURL(lhs.url, rhs.url),
            canonicalURL: preferredCanonicalURL(lhs.canonicalURL, rhs.canonicalURL),
            title: preferredTitle(lhs.title, rhs.title),
            summary: preferredTextPayload(lhs.summary, rhs.summary),
            contentHTML: preferredHTMLContent(lhs.contentHTML, rhs.contentHTML),
            contentText: preferredTextPayload(lhs.contentText, rhs.contentText),
            author: preferredAuthor(lhs.author, rhs.author),
            publishedAtRaw: publishedDate.rawValue,
            updatedAtRaw: updatedDate.rawValue,
            publishedAt: publishedDate.parsedValue,
            updatedAt: updatedDate.parsedValue,
            imageURL: preferredMediaURL(lhs.imageURL, rhs.imageURL)
        )
    }

    private static func preferredIdentityValue(_ lhs: String?, _ rhs: String?) -> String? {
        let left = normalized(lhs)
        let right = normalized(rhs)

        switch (left, right) {
        case (.none, .none):
            return nil
        case let (.some(value), .none), let (.none, .some(value)):
            return value
        case let (.some(leftValue), .some(rightValue)):
            return leftValue == rightValue ? leftValue : (leftValue.count >= rightValue.count ? leftValue : rightValue)
        }
    }

    private static func preferredArticleURL(_ lhs: String?, _ rhs: String?) -> String? {
        preferredURL(lhs, rhs, preferShorterPath: false)
    }

    private static func preferredCanonicalURL(_ lhs: String?, _ rhs: String?) -> String? {
        preferredURL(lhs, rhs, preferShorterPath: true)
    }

    private static func preferredMediaURL(_ lhs: String?, _ rhs: String?) -> String? {
        preferredURL(lhs, rhs, preferShorterPath: false)
    }

    private static func preferredTitle(_ lhs: String?, _ rhs: String?) -> String? {
        preferredString(lhs, rhs) { value in
            var score = value.count
            if value.count >= 12 { score += 8 }
            if value.contains("http://") == false && value.contains("https://") == false { score += 8 }
            if value.rangeOfCharacter(from: .letters) != nil { score += 6 }
            return score
        }
    }

    private static func preferredTextPayload(_ lhs: String?, _ rhs: String?) -> String? {
        preferredString(lhs, rhs) { value in
            var score = value.count
            let lineCount = value.split(separator: "\n").count
            if lineCount > 1 { score += 10 }
            if value.rangeOfCharacter(from: .letters) != nil { score += 6 }
            return score
        }
    }

    private static func preferredHTMLContent(_ lhs: String?, _ rhs: String?) -> String? {
        preferredString(lhs, rhs) { value in
            var score = value.count
            if value.contains("<") && value.contains(">") { score += 20 }
            if value.contains("<p") || value.contains("<div") || value.contains("<article") { score += 12 }
            return score
        }
    }

    private static func preferredAuthor(_ lhs: String?, _ rhs: String?) -> String? {
        preferredString(lhs, rhs) { value in
            var score = value.count
            if value.contains("@") == false { score += 6 }
            if value.contains("http://") == false && value.contains("https://") == false { score += 4 }
            return score
        }
    }

    private static func preferredURL(_ lhs: String?, _ rhs: String?, preferShorterPath: Bool) -> String? {
        preferredString(lhs, rhs) { value in
            urlScore(for: value, preferShorterPath: preferShorterPath)
        }
    }

    private static func preferredString(
        _ lhs: String?,
        _ rhs: String?,
        score: (String) -> Int
    ) -> String? {
        let left = normalized(lhs)
        let right = normalized(rhs)

        switch (left, right) {
        case (.none, .none):
            return nil
        case let (.some(value), .none), let (.none, .some(value)):
            return value
        case let (.some(leftValue), .some(rightValue)):
            let leftScore = score(leftValue)
            let rightScore = score(rightValue)
            if rightScore == leftScore {
                return leftValue.count >= rightValue.count ? leftValue : rightValue
            }
            return rightScore > leftScore ? rightValue : leftValue
        }
    }

    private static func urlScore(for value: String, preferShorterPath: Bool) -> Int {
        guard let components = URLComponents(string: value) else {
            return value.count
        }

        var score = value.count
        if let scheme = components.scheme?.lowercased(), scheme == "https" {
            score += 20
        } else if let scheme = components.scheme?.lowercased(), scheme == "http" {
            score += 10
        }

        if let host = components.host, host.isEmpty == false {
            score += 20
        }

        if components.fragment == nil {
            score += 6
        }

        if let query = components.percentEncodedQuery, query.isEmpty == false {
            score -= min(query.count, 24)
        }

        let pathLength = components.percentEncodedPath.count
        score += preferShorterPath ? max(0, 16 - min(pathLength, 16)) : min(pathLength, 16)

        return score
    }

    private enum DateSelectionStrategy {
        case earliest
        case latest
    }

    private struct DateValue {
        let rawValue: String?
        let parsedValue: Date?
    }

    private static func preferredDate(
        lhsRawValue: String?,
        lhsParsedValue: Date?,
        rhsRawValue: String?,
        rhsParsedValue: Date?,
        strategy: DateSelectionStrategy
    ) -> DateValue {
        let left = normalized(lhsRawValue).map {
            DateValue(
                rawValue: $0,
                parsedValue: lhsParsedValue ?? FeedDateParsingService.parse($0)
            )
        }
        let right = normalized(rhsRawValue).map {
            DateValue(
                rawValue: $0,
                parsedValue: rhsParsedValue ?? FeedDateParsingService.parse($0)
            )
        }

        switch (left, right) {
        case (.none, .none):
            return DateValue(rawValue: nil, parsedValue: nil)
        case let (.some(value), .none), let (.none, .some(value)):
            return value
        case let (.some(left), .some(right)):
            switch (left.parsedValue, right.parsedValue) {
            case let (.some(leftDate), .some(rightDate)):
                switch strategy {
                case .earliest:
                    return leftDate <= rightDate ? left : right
                case .latest:
                    return leftDate >= rightDate ? left : right
                }
            case (.some, .none):
                return left
            case (.none, .some):
                return right
            case (.none, .none):
                return (left.rawValue?.count ?? 0) >= (right.rawValue?.count ?? 0) ? left : right
            }
        }
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedValue.isEmpty ? nil : normalizedValue
    }
}
